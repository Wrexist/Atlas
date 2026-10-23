import Foundation

/// Bridges DataStore + HealthKit + StoreService into the
/// `BioAgeHeroSection.BioAgeState` the Biology tab consumes.
/// Pure orchestration — no rendering, no @Observable surface — so the
/// view's state-change logic stays a one-liner and the math lives in
/// `PerformanceAgeEngine`, where it is tested in isolation.
@MainActor
enum BioAgeStateResolver {

    /// Default chronological age fallback when the user hasn't entered
    /// their age yet. Picks the midpoint of the typical cohort so the
    /// dial's scale labels (±5 years) read as recognisable numbers. Only
    /// ever anchors the scale — it is never fed to the engine.
    static let chronologicalAgeFallback: Int = 35

    /// The estimate's reference curves are adult norms, so it is never
    /// computed below this age.
    static let minimumAge: Int = 18

    /// How far back HealthKit is read: the trend plus the window its
    /// oldest point looks back over.
    static let historyDays: Int = PerformanceAgeEngine.trendDays + PerformanceAgeEngine.windowDays
    /// VO2 max is read over its own, longer window, so its read reaches
    /// further back.
    static let vo2HistoryDays: Int = PerformanceAgeEngine.trendDays + PerformanceAgeEngine.vo2WindowDays

    /// Resolves the Biological Age state for the current moment. The Pro
    /// check + HealthKit reads happen inside; callers pass only what lives
    /// in the profile.
    ///
    /// - Parameter chronologicalAge: User's age in years. `nil` or under
    ///   `minimumAge` resolves Pro users to `.needsAge` rather than an
    ///   estimate; the dial's scale falls back to `chronologicalAgeFallback`.
    /// - Parameter sex: Picks the VO2 max reference curve.
    /// - Parameter bodyMassIndex: From profile height and latest weight.
    /// - Parameter weightHistory: The in-app weight log.
    /// - Parameter isPro: When false the resolver short-circuits to
    ///   `.locked` without touching HealthKit.
    static func resolve(
        chronologicalAge: Int?,
        sex: BiologicalSex = .unspecified,
        bodyMassIndex: Double? = nil,
        weightHistory: [WeightEntry] = [],
        isPro: Bool
    ) async -> Resolved {
        let scaleAge = chronologicalAge ?? chronologicalAgeFallback
        guard isPro else {
            return Resolved(state: .locked, chronologicalAge: scaleAge)
        }
        guard let age = chronologicalAge, age >= minimumAge else {
            return Resolved(state: .needsAge, chronologicalAge: scaleAge)
        }

        let series = await readSeries(weightHistory: weightHistory)
        let profile = PerformanceAgeEngine.Profile(
            chronologicalAge: age,
            sex: sex,
            bodyMassIndex: bodyMassIndex
        )
        let today = Date()
        let inputs = PerformanceAgeEngine.inputs(asOf: today, series: series, profile: profile)

        if let estimate = PerformanceAgeEngine.estimate(inputs: inputs) {
            return Resolved(
                state: .unlocked(estimate: estimate),
                chronologicalAge: age,
                inputs: inputs,
                trend: PerformanceAgeEngine.trend(series: series, profile: profile, endingOn: today)
            )
        }

        return Resolved(state: buildingState(for: inputs), chronologicalAge: age, inputs: inputs)
    }

    /// Pro user without enough data yet. The day target comes from the
    /// engine's own confidence gate for the signals present, so the count
    /// shown is the day the estimate actually unlocks; nil when only more
    /// signals can unlock it.
    static func buildingState(for inputs: PerformanceAgeEngine.Inputs) -> BioAgeHeroSection.BioAgeState {
        let kinds = PerformanceAgeEngine.drivers(for: inputs).map(\.kind)
        let coverage = PerformanceAgeEngine.coverage(of: kinds)
        return .building(days: inputs.healthDataDays,
                         requiredDays: PerformanceAgeEngine.minimumDays(forCoverage: coverage))
    }

    /// Fans the HealthKit reads out in parallel. Coverage is the union of
    /// HRV, resting-HR and sleep days (computed in the engine), so a
    /// tracker that writes resting heart rate and sleep but no HRV still
    /// builds a baseline.
    private static func readSeries(weightHistory: [WeightEntry]) async -> PerformanceAgeEngine.DailySeries {
        let kit = HealthKitService.shared
        let days = historyDays
        async let hrv = kit.dailyHRV(days: days)
        async let rhr = kit.dailyRestingHeartRate(days: days)
        async let sleep = kit.dailySleepHours(days: days)
        async let steps = kit.dailySteps(days: days)
        async let vo2 = kit.dailyVO2Max(days: vo2HistoryDays)
        // Bound one at a time because Swift rejects `await` to the right of
        // a non-assignment operator. All five are already in flight.
        let hrvDays = await hrv
        let rhrDays = await rhr
        let sleepDays = await sleep
        let stepDays = await steps
        let vo2Days = await vo2
        return PerformanceAgeEngine.DailySeries(
            hrv: hrvDays.map(dailyValue),
            rhr: rhrDays.map(dailyValue),
            sleepHours: sleepDays.map(dailyValue),
            steps: stepDays.map(dailyValue),
            vo2Max: vo2Days.map(dailyValue),
            weightKg: weightHistory.map { .init(date: $0.date, value: $0.kg) }
        )
    }

    nonisolated private static func dailyValue(_ sample: (date: Date, value: Double)) -> PerformanceAgeEngine.DailyValue {
        .init(date: sample.date, value: sample.value)
    }

    /// What the view consumes. Carries `chronologicalAge` so the dial
    /// knows where to anchor its scale even in the locked state, and the
    /// engine inputs so the page can show which signals are present.
    struct Resolved: Equatable, Sendable {
        let state: BioAgeHeroSection.BioAgeState
        let chronologicalAge: Int
        /// `nil` when locked — HealthKit was never read.
        let inputs: PerformanceAgeEngine.Inputs?
        /// Oldest first; empty unless unlocked.
        let trend: [PerformanceAgeEngine.TrendPoint]

        init(
            state: BioAgeHeroSection.BioAgeState,
            chronologicalAge: Int,
            inputs: PerformanceAgeEngine.Inputs? = nil,
            trend: [PerformanceAgeEngine.TrendPoint] = []
        ) {
            self.state = state
            self.chronologicalAge = chronologicalAge
            self.inputs = inputs
            self.trend = trend
        }
    }
}
