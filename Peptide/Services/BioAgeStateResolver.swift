import Foundation

/// Bridges DataStore + HealthKit + StoreService into the
/// `BioAgeHeroSection.BioAgeState` the Biology tab consumes.
/// Pure orchestration — no rendering, no @Observable surface
/// — so the view's state-change logic stays a one-liner and
/// the gnarly "30 days of HRV medians cross-checked against the
/// user's age" math gets tested in isolation.
@MainActor
enum BioAgeStateResolver {

    /// Days of HealthKit history required before the engine even
    /// attempts an estimate. Matches `PerformanceAgeEngine`'s
    /// density curve — below 7 days the engine returns nil; below
    /// the engine's `minConfidence` we still want the "building"
    /// state to surface progress, not a permanent locked tile.
    static let minBaselineDays: Int = 7

    /// Default chronological age fallback when the user hasn't
    /// entered their age yet. Picks the midpoint of the typical
    /// peptide-tracker cohort so the locked dial's scale labels
    /// (±5 years) read as recognisable numbers in marketing
    /// screenshots before onboarding completes. Once the user
    /// fills in their age in Profile, the live value takes over.
    static let chronologicalAgeFallback: Int = 35

    /// Resolves the Bio Age state for the current moment. The
    /// Pro check + HealthKit reads happen inside; callers pass
    /// only the lightweight inputs (chronological age, recent
    /// weight delta) the bio-age engine can't pull on its own.
    ///
    /// - Parameter chronologicalAge: User's chronological age in
    ///   years. Pass `nil` to fall back to
    ///   `chronologicalAgeFallback` — the view's number scale
    ///   still renders without it.
    /// - Parameter weightDeltaKg30d: 30-day weight delta in
    ///   kilograms, if computable from WeightEntry history.
    /// - Parameter isPro: Pro entitlement flag. When false the
    ///   resolver short-circuits to `.locked` regardless of how
    ///   much HealthKit data the user has.
    static func resolve(
        chronologicalAge: Int?,
        weightDeltaKg30d: Double?,
        isPro: Bool
    ) async -> Resolved {
        let age = chronologicalAge ?? chronologicalAgeFallback
        guard isPro else {
            return Resolved(state: .locked, chronologicalAge: age)
        }

        let kit = HealthKitService.shared
        async let hrv      = kit.averageHRV(days: 30)
        async let rhr      = kit.averageRestingHeartRate(days: 30)
        async let sleep    = kit.averageSleepHours(days: 30)
        // Real day-coverage via `dailyHRV()` which returns one value
        // per calendar day with samples present. The previous
        // approach passed 30 unconditionally whenever `averageHRV`
        // came back non-nil, so a user with 1 day of HRV got
        // density factor 1.0 and a real Bio Age estimate after a
        // single morning (audit Biology H7). The confidence curve
        // in PerformanceAgeEngine is tuned for actual sample
        // density; feed it the real number, which also obsoletes
        // the `minBaselineDays`-floor workaround on main.
        //
        // Coverage is the *union* of days across all three series, not HRV
        // alone. Plenty of trackers write resting heart rate and sleep but
        // no HRV at all; keying on HRV left those users pinned at
        // "building baseline" forever no matter how long they wore the
        // device.
        async let hrvDaily = kit.dailyHRV(days: 30)
        async let rhrDaily = kit.dailyRestingHeartRate(days: 30)
        async let sleepDaily = kit.dailySleepHours(days: 30)
        let hrvValue = await hrv
        let rhrValue = await rhr
        let sleepValue = await sleep
        let calendar = Calendar.current
        let coveredDays = Set(
            (await hrvDaily + await rhrDaily + await sleepDaily)
                .map { calendar.startOfDay(for: $0.date) }
        )
        let dataDays = coveredDays.count

        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: age,
            hrvMedian30d: hrvValue,
            rhrMedian30d: rhrValue,
            sleepHoursMedian30d: sleepValue,
            weightDeltaKg30d: weightDeltaKg30d,
            healthDataDays: dataDays
        )

        if let estimate = PerformanceAgeEngine.estimate(inputs: inputs) {
            return Resolved(state: .unlocked(estimate: estimate), chronologicalAge: age)
        }

        // Pro user but not enough data yet. Progress is now anchored
        // to the actual `dataDays / minBaselineDays` ratio so the
        // "N of 7 days collected" copy in BioAgeHeroSection reflects
        // the real day count instead of the present-signals-out-of-3
        // approximation (audit Biology H6).
        let progress = min(1.0, Double(dataDays) / Double(minBaselineDays))
        return Resolved(state: .building(progress: progress), chronologicalAge: age)
    }

    /// What the view consumes. Carries `chronologicalAge` so the
    /// dial knows where to anchor its scale even in the locked
    /// state — the dial labels at ±5 years remain meaningful
    /// without exposing the bio-age estimate.
    struct Resolved: Equatable, Sendable {
        let state: BioAgeHeroSection.BioAgeState
        let chronologicalAge: Int
    }
}

// MARK: - BioAgeState Equatable conformance hop

extension BioAgeHeroSection.BioAgeState {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.locked, .locked):
            return true
        case (.building(let a), .building(let b)):
            return a == b
        case (.unlocked(let a), .unlocked(let b)):
            return a == b
        default:
            return false
        }
    }
}
