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
        async let hrv   = kit.averageHRV(days: 30)
        async let rhr   = kit.averageRestingHeartRate(days: 30)
        async let sleep = kit.averageSleepHours(days: 30)
        // Day count is approximated from the HealthKit
        // averageHRV being non-nil; a proper "samples in window"
        // count would need a dedicated query. For the
        // PerformanceAgeEngine confidence curve, we pass 30
        // (full window) when HRV came back, 0 otherwise — the
        // engine treats < 7 days as zero confidence anyway.
        let hrvValue = await hrv
        let rhrValue = await rhr
        let sleepValue = await sleep
        let dataDays = hrvValue != nil ? 30 : 0

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

        // Pro user but not enough data yet. Surface progress so
        // the user sees a path to value, not a permanent block.
        // Without a real "samples-per-day" count we approximate
        // progress as how many of HRV / RHR / Sleep came back —
        // each present signal pushes toward 1.0.
        let presentSignals = [hrvValue, rhrValue, sleepValue]
            .compactMap { $0 }
            .count
        let progress = Double(presentSignals) / 3.0
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
