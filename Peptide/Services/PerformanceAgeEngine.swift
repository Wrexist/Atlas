import Foundation

/// Biological Age estimator. Pure functions over a snapshot of the user's
/// biometrics — no HealthKit reads inside, so the math can be exhaustively
/// unit-tested without standing up a HealthKit store.
///
/// **Not a medical-grade biomarker.** The output is an estimate based on
/// the user's personal biometrics — a directional read on whether their
/// cardio fitness, recovery, sleep, activity and body composition are
/// pulling their effective age younger or older than their chronological
/// age. The UI must surface that hedge explicitly.
///
/// Algorithm sketch:
///   1. Anchor at `chronologicalAge`.
///   2. Each present signal contributes a signed delta in years from a
///      deterministic, bounded curve (see the constants below). Signals
///      that decline with age anyway — VO2 max and HRV — are read against
///      an age-adjusted reference, so normal ageing isn't counted twice.
///   3. Sum the deltas, cap total drift at ±`maxDriftYears` so a single
///      great month can't claim to roll back a decade.
///   4. Confidence = signal coverage (weighted by how strongly each signal
///      tracks ageing) × data density (days of history behind the medians).
///   5. Below `minConfidence`, return nil. The UI shows the "building
///      baseline" state instead of a number it can't stand behind.
///
/// Every curve is a conservative heuristic drawn from population-level
/// associations, not a fitted clinical model. The per-signal swings are
/// deliberately small, and the largest goes to VO2 max because it is the
/// fitness marker most consistently associated with ageing.
enum PerformanceAgeEngine {

    // MARK: - Public types

    struct Inputs: Equatable, Sendable {
        let chronologicalAge: Int
        /// Used only to pick the VO2 max reference curve.
        let sex: BiologicalSex
        let hrvMedian30d: Double?
        let rhrMedian30d: Double?
        /// Median hours asleep per night (not efficiency). Efficiency would
        /// need stage data we don't reliably have.
        let sleepHoursMedian30d: Double?
        let weightDeltaKg30d: Double?
        /// Median Apple Health cardio-fitness estimate (ml/kg/min) over the
        /// last `vo2WindowDays`. Sparse by nature — the watch only writes
        /// one after an outdoor walk, run or hike.
        let vo2MaxRecent: Double?
        let stepsMedian30d: Double?
        /// From the profile's height and latest weight.
        let bodyMassIndex: Double?
        /// Days of HealthKit HRV / resting-HR / sleep data backing the
        /// medians — drives confidence.
        let healthDataDays: Int

        init(
            chronologicalAge: Int,
            sex: BiologicalSex = .unspecified,
            hrvMedian30d: Double? = nil,
            rhrMedian30d: Double? = nil,
            sleepHoursMedian30d: Double? = nil,
            weightDeltaKg30d: Double? = nil,
            vo2MaxRecent: Double? = nil,
            stepsMedian30d: Double? = nil,
            bodyMassIndex: Double? = nil,
            healthDataDays: Int = 0
        ) {
            self.chronologicalAge = chronologicalAge
            self.sex = sex
            self.hrvMedian30d = hrvMedian30d
            self.rhrMedian30d = rhrMedian30d
            self.sleepHoursMedian30d = sleepHoursMedian30d
            self.weightDeltaKg30d = weightDeltaKg30d
            self.vo2MaxRecent = vo2MaxRecent
            self.stepsMedian30d = stepsMedian30d
            self.bodyMassIndex = bodyMassIndex
            self.healthDataDays = healthDataDays
        }
    }

    struct Estimate: Equatable, Sendable {
        let biologicalAge: Double
        let confidence: Double
        /// Present signals, sorted by absolute impact, largest first.
        let drivers: [Driver]
        /// Signals the estimate could use but had no data for.
        let missing: [Driver.Kind]

        init(
            biologicalAge: Double,
            confidence: Double,
            drivers: [Driver],
            missing: [Driver.Kind] = []
        ) {
            self.biologicalAge = biologicalAge
            self.confidence = confidence
            self.drivers = drivers
            self.missing = missing
        }
    }

    struct Driver: Equatable, Sendable, Identifiable {
        var id: String { kind.rawValue }
        let kind: Kind
        /// Signed delta in years this signal contributed.
        /// Positive = older; negative = younger.
        let deltaYears: Double
        /// The user's reading, in the signal's own unit.
        let value: Double?
        /// The reading at which this signal contributes nothing — the
        /// age-adjusted typical value, or the target the curve is built
        /// around.
        let reference: Double?

        init(kind: Kind, deltaYears: Double, value: Double? = nil, reference: Double? = nil) {
            self.kind = kind
            self.deltaYears = deltaYears
            self.value = value
            self.reference = reference
        }

        /// Declaration order is the tie-break order for equal impacts.
        enum Kind: String, Sendable, CaseIterable {
            case vo2Max, hrv, rhr, sleep, steps, bodyMassIndex, weight

            /// How much this signal counts toward coverage. Reflects how
            /// strongly each one tracks ageing; sums to 1.
            var coverageWeight: Double {
                switch self {
                case .vo2Max:        return 0.25
                case .hrv:           return 0.20
                case .rhr:           return 0.20
                case .sleep:         return 0.15
                case .steps:         return 0.10
                case .bodyMassIndex: return 0.05
                case .weight:        return 0.05
                }
            }

            /// Largest pull, in years, this signal can exert either way.
            var maxSwingYears: Double {
                switch self {
                case .vo2Max:        return PerformanceAgeEngine.vo2SwingYears
                case .hrv:           return PerformanceAgeEngine.hrvSwingYears
                case .rhr:           return PerformanceAgeEngine.rhrSwingYears
                case .sleep:         return PerformanceAgeEngine.sleepPenaltyYears
                case .steps:         return PerformanceAgeEngine.stepsSwingYears
                case .bodyMassIndex: return PerformanceAgeEngine.bmiHighPenaltyYears
                case .weight:        return PerformanceAgeEngine.weightTrendPenaltyYears
                }
            }
        }
    }

    // MARK: - Algorithm constants

    /// Bound on total drift from chronological age. Published bio-age
    /// estimators rarely exceed ±10 years for non-pathological
    /// populations; a tighter cap keeps the UI honest.
    static let maxDriftYears: Double = 8.0

    /// Minimum confidence below which the engine returns nil and the UI
    /// surfaces the "building baseline" state.
    static let minConfidence: Double = 0.6

    /// Coverage weight at which completeness reaches 1. Below the full 1.0
    /// on purpose: HRV + resting HR + sleep + weight — what most Apple
    /// Watch wearers have — is a complete enough picture.
    static let fullCoverageWeight: Double = 0.6

    /// Trailing window for the daily medians.
    static let windowDays: Int = 30
    /// VO2 max estimates are sparse, so they get a longer window.
    static let vo2WindowDays: Int = 90

    /// HRV thresholds in milliseconds at `hrvReferenceAge`. Above
    /// `hrvHighFloor` → up to `-hrvSwingYears`; below `hrvLowCeiling` → up
    /// to `+hrvSwingYears`. Linear interpolation between.
    static let hrvLowCeiling: Double = 25
    static let hrvHighFloor: Double = 60
    static let hrvSwingYears: Double = 2.5
    /// SDNN falls with age in healthy people. Past the reference age both
    /// thresholds slide down by this much per year, up to a bounded shift,
    /// so a 60-year-old isn't read as "old" for having a 60-year-old's HRV.
    static let hrvReferenceAge: Int = 30
    static let hrvAgeDeclinePerYear: Double = 0.5
    static let hrvMaxAgeShift: Double = 15

    static let rhrAthleticCeiling: Double = 55      // ≤ this → up to -years
    static let rhrElevatedFloor: Double = 75        // ≥ this → up to +years
    static let rhrSwingYears: Double = 1.8

    static let sleepFloor: Double = 6.0             // ≤ this → +years
    static let sleepTarget: Double = 7.5            // ≥ this → 0 contribution
    static let sleepPenaltyYears: Double = 1.5

    /// Weight-trend signal. Either direction past the threshold counts as
    /// +0.5 years (rapid change in either direction stresses the system);
    /// slow drift is ignored.
    static let weightRapidDeltaKg: Double = 2.0
    static let weightTrendPenaltyYears: Double = 0.5

    /// VO2 max reference: a linear approximation of population medians,
    /// `base − decline × (age − 25)`, per sex. Each `vo2UnitsPerYear` of
    /// ml/kg/min above or below the reference moves the estimate a year,
    /// bounded at `vo2SwingYears`.
    static let vo2ReferenceAge: Int = 25
    static let vo2BaseMale: Double = 44
    static let vo2BaseFemale: Double = 37
    static let vo2DeclineMale: Double = 0.32
    static let vo2DeclineFemale: Double = 0.27
    static let vo2UnitsPerYear: Double = 2.0
    static let vo2SwingYears: Double = 3.0

    /// Daily steps. The association with outcomes flattens out somewhere
    /// in the 7–10k range, so the curve stops rewarding at `stepsHigh`.
    static let stepsLow: Double = 4_000
    static let stepsHigh: Double = 10_000
    static let stepsSwingYears: Double = 1.0

    /// BMI only ever penalises, and gently — it can't tell muscle from
    /// fat, so it carries the smallest weight of any signal.
    static let bmiUnderweightCeiling: Double = 18.5
    static let bmiHealthyCeiling: Double = 27
    static let bmiHighFloor: Double = 35
    static let bmiHighPenaltyYears: Double = 1.5
    static let bmiUnderweightPenaltyYears: Double = 0.5

    // MARK: - Estimate

    static func estimate(inputs: Inputs) -> Estimate? {
        let present = drivers(for: inputs)
        let presentKinds = present.map(\.kind)
        let confidence = confidenceScore(
            coverage: coverage(of: presentKinds),
            healthDataDays: inputs.healthDataDays
        )
        guard confidence >= minConfidence else { return nil }

        let summedDelta = present.map(\.deltaYears).reduce(0, +)
        let cappedDelta = max(-maxDriftYears, min(maxDriftYears, summedDelta))

        return Estimate(
            biologicalAge: Double(inputs.chronologicalAge) + cappedDelta,
            confidence: confidence,
            drivers: sortedByImpact(present),
            missing: Driver.Kind.allCases.filter { !presentKinds.contains($0) }
        )
    }

    /// One driver per signal with a usable reading. Zero, negative and
    /// non-finite readings are treated as missing rather than scored, so a
    /// broken sample can't count toward coverage.
    static func drivers(for inputs: Inputs) -> [Driver] {
        let age = inputs.chronologicalAge
        var result: [Driver] = []

        if let vo2 = usable(inputs.vo2MaxRecent) {
            result.append(.init(kind: .vo2Max,
                                 deltaYears: vo2MaxContribution(vo2Max: vo2, age: age, sex: inputs.sex),
                                 value: vo2,
                                 reference: vo2MaxReference(age: age, sex: inputs.sex)))
        }
        if let hrv = usable(inputs.hrvMedian30d) {
            result.append(.init(kind: .hrv,
                                 deltaYears: hrvContribution(hrv: hrv, age: age),
                                 value: hrv,
                                 reference: hrvReference(age: age)))
        }
        if let rhr = usable(inputs.rhrMedian30d) {
            result.append(.init(kind: .rhr,
                                 deltaYears: rhrContribution(rhr: rhr),
                                 value: rhr,
                                 reference: (rhrAthleticCeiling + rhrElevatedFloor) / 2))
        }
        if let sleep = usable(inputs.sleepHoursMedian30d) {
            result.append(.init(kind: .sleep,
                                 deltaYears: sleepContribution(hours: sleep),
                                 value: sleep,
                                 reference: sleepTarget))
        }
        if let steps = usable(inputs.stepsMedian30d) {
            result.append(.init(kind: .steps,
                                 deltaYears: stepsContribution(steps: steps),
                                 value: steps,
                                 reference: (stepsLow + stepsHigh) / 2))
        }
        if let bmi = usable(inputs.bodyMassIndex) {
            result.append(.init(kind: .bodyMassIndex,
                                 deltaYears: bmiContribution(bmi: bmi),
                                 value: bmi,
                                 reference: bmiHealthyCeiling))
        }
        if let weight = inputs.weightDeltaKg30d, weight.isFinite {
            result.append(.init(kind: .weight,
                                 deltaYears: weightContribution(deltaKg: weight),
                                 value: weight,
                                 reference: weightRapidDeltaKg))
        }
        return result
    }

    // MARK: - Component contributions (testable in isolation)

    /// Age-adjusted midpoint of the HRV curve — the reading that
    /// contributes nothing.
    static func hrvReference(age: Int) -> Double {
        (hrvLowCeiling + hrvHighFloor) / 2 - hrvAgeShift(age: age)
    }

    private static func hrvAgeShift(age: Int) -> Double {
        let yearsPast = Double(max(0, age - hrvReferenceAge))
        return min(hrvMaxAgeShift, yearsPast * hrvAgeDeclinePerYear)
    }

    /// Maps HRV ms → signed years delta, thresholds shifted for age.
    ///   Above the high floor → -hrvSwingYears (younger)
    ///   Below the low ceiling → +hrvSwingYears (older)
    ///   Linear interpolation between.
    static func hrvContribution(hrv: Double, age: Int = hrvReferenceAge) -> Double {
        guard hrv > 0 else { return 0 }
        let shift = hrvAgeShift(age: age)
        let low = hrvLowCeiling - shift
        let high = hrvHighFloor - shift
        if hrv >= high { return -hrvSwingYears }
        if hrv <= low { return hrvSwingYears }
        let normalized = (hrv - low) / (high - low) // 0…1
        return hrvSwingYears - normalized * (2 * hrvSwingYears)
    }

    /// Maps RHR bpm → signed years delta.
    ///   ≤ 55 → -rhrSwingYears (athletic, younger)
    ///   ≥ 75 → +rhrSwingYears (elevated, older)
    ///   Linear between.
    static func rhrContribution(rhr: Double) -> Double {
        guard rhr > 0 else { return 0 }
        if rhr <= rhrAthleticCeiling { return -rhrSwingYears }
        if rhr >= rhrElevatedFloor { return rhrSwingYears }
        let normalized = (rhr - rhrAthleticCeiling) / (rhrElevatedFloor - rhrAthleticCeiling)
        return -rhrSwingYears + normalized * (2 * rhrSwingYears)
    }

    /// Sleep contribution. Below the floor we penalise; above target we
    /// don't reward — long sleep isn't a clean signal of being "younger"
    /// without more context. Between floor and target the penalty scales
    /// linearly.
    static func sleepContribution(hours: Double) -> Double {
        guard hours > 0 else { return 0 }
        if hours >= sleepTarget { return 0 }
        if hours <= sleepFloor { return sleepPenaltyYears }
        let deficit = (sleepTarget - hours) / (sleepTarget - sleepFloor)
        return sleepPenaltyYears * deficit
    }

    /// Weight-trend contribution. Magnitude of change matters, not
    /// direction. Slow drift below the threshold is ignored.
    static func weightContribution(deltaKg: Double) -> Double {
        abs(deltaKg) >= weightRapidDeltaKg ? weightTrendPenaltyYears : 0
    }

    /// Typical VO2 max (ml/kg/min) for this age and sex. `.other` and
    /// `.unspecified` use the midpoint of the two curves.
    static func vo2MaxReference(age: Int, sex: BiologicalSex) -> Double {
        let years = Double(max(0, age - vo2ReferenceAge))
        let male = vo2BaseMale - vo2DeclineMale * years
        let female = vo2BaseFemale - vo2DeclineFemale * years
        switch sex {
        case .male:   return male
        case .female: return female
        case .other, .unspecified: return (male + female) / 2
        }
    }

    /// VO2 max above the age reference reads younger, below reads older,
    /// one year per `vo2UnitsPerYear`, bounded at ±`vo2SwingYears`.
    static func vo2MaxContribution(vo2Max: Double, age: Int, sex: BiologicalSex) -> Double {
        guard vo2Max > 0 else { return 0 }
        let delta = -(vo2Max - vo2MaxReference(age: age, sex: sex)) / vo2UnitsPerYear
        return max(-vo2SwingYears, min(vo2SwingYears, delta))
    }

    /// Daily steps → signed years delta.
    ///   ≤ 4,000 → +stepsSwingYears; ≥ 10,000 → -stepsSwingYears.
    ///   Linear between, neutral at 7,000.
    static func stepsContribution(steps: Double) -> Double {
        guard steps > 0 else { return 0 }
        if steps >= stepsHigh { return -stepsSwingYears }
        if steps <= stepsLow { return stepsSwingYears }
        let normalized = (steps - stepsLow) / (stepsHigh - stepsLow)
        return stepsSwingYears - normalized * (2 * stepsSwingYears)
    }

    /// BMI → years, penalty only. 18.5–27 is neutral; above 27 the penalty
    /// grows linearly to `bmiHighPenaltyYears` at 35; under 18.5 is a flat
    /// small penalty.
    static func bmiContribution(bmi: Double) -> Double {
        guard bmi > 0 else { return 0 }
        if bmi < bmiUnderweightCeiling { return bmiUnderweightPenaltyYears }
        if bmi <= bmiHealthyCeiling { return 0 }
        if bmi >= bmiHighFloor { return bmiHighPenaltyYears }
        let normalized = (bmi - bmiHealthyCeiling) / (bmiHighFloor - bmiHealthyCeiling)
        return bmiHighPenaltyYears * normalized
    }

    /// BMI from the profile, or nil when either number is missing or
    /// implausible (a height typed in inches into a centimetre field).
    static func bodyMassIndex(weightKg: Double?, heightCm: Double?) -> Double? {
        guard let weightKg, let heightCm,
              weightKg > 0, (100...250).contains(heightCm) else { return nil }
        let meters = heightCm / 100
        let bmi = weightKg / (meters * meters)
        return (10...80).contains(bmi) ? bmi : nil
    }

    // MARK: - Confidence

    /// Weighted share of the signals present, normalised so that
    /// `fullCoverageWeight` counts as complete. 0…1.
    static func coverage(of kinds: [Driver.Kind]) -> Double {
        let weight = Set(kinds).reduce(0.0) { $0 + $1.coverageWeight }
        return min(1, weight / fullCoverageWeight)
    }

    /// Coverage × data density. 30 days = full density; 7 days = 0.4;
    /// fewer than 7 days = unusable.
    static func confidenceScore(coverage: Double, healthDataDays: Int) -> Double {
        let densityFactor: Double
        if healthDataDays < 7 {
            densityFactor = 0
        } else if healthDataDays >= windowDays {
            densityFactor = 1
        } else {
            densityFactor = 0.4 + Double(healthDataDays - 7) / 23 * 0.6
        }
        return max(0, min(1, coverage)) * densityFactor
    }

    // MARK: - From daily series

    struct DailyValue: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    /// Raw daily series the estimate and its trend are computed from.
    struct DailySeries: Equatable, Sendable {
        var hrv: [DailyValue] = []
        var rhr: [DailyValue] = []
        var sleepHours: [DailyValue] = []
        var steps: [DailyValue] = []
        var vo2Max: [DailyValue] = []
        var weightKg: [DailyValue] = []
    }

    /// Profile facts that don't vary across the trend window.
    struct Profile: Equatable, Sendable {
        let chronologicalAge: Int
        var sex: BiologicalSex = .unspecified
        var bodyMassIndex: Double?
    }

    struct TrendPoint: Equatable, Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let biologicalAge: Double
    }

    /// Engine inputs as they stood on `day`: medians over the trailing
    /// `windowDays` (VO2 max over `vo2WindowDays`), the weight change
    /// across that window, and the count of days with any recovery data.
    static func inputs(
        asOf day: Date,
        series: DailySeries,
        profile: Profile,
        calendar: Calendar = .current
    ) -> Inputs {
        let recent = window(endingOn: day, days: windowDays, calendar: calendar)
        let vo2Window = window(endingOn: day, days: vo2WindowDays, calendar: calendar)

        let hrv = series.hrv.filter { recent.contains($0.date) }
        let rhr = series.rhr.filter { recent.contains($0.date) }
        let sleep = series.sleepHours.filter { recent.contains($0.date) }
        let coveredDays = Set((hrv + rhr + sleep).map { calendar.startOfDay(for: $0.date) })

        return Inputs(
            chronologicalAge: profile.chronologicalAge,
            sex: profile.sex,
            hrvMedian30d: median(hrv.map(\.value)),
            rhrMedian30d: median(rhr.map(\.value)),
            sleepHoursMedian30d: median(sleep.map(\.value)),
            weightDeltaKg30d: weightDelta(series.weightKg.filter { recent.contains($0.date) }),
            vo2MaxRecent: median(series.vo2Max.filter { vo2Window.contains($0.date) }.map(\.value)),
            stepsMedian30d: median(series.steps.filter { recent.contains($0.date) }.map(\.value)),
            bodyMassIndex: profile.bodyMassIndex,
            healthDataDays: coveredDays.count
        )
    }

    /// The estimate recomputed every `strideDays` across the last `days`,
    /// oldest first, ending on `endDay`. Points where the engine wouldn't
    /// commit to a number are left out rather than guessed. BMI is the
    /// current value throughout — the profile keeps no height history.
    static func trend(
        series: DailySeries,
        profile: Profile,
        endingOn endDay: Date,
        days: Int = 90,
        strideDays: Int = 7,
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        guard days > 0, strideDays > 0 else { return [] }
        let end = calendar.startOfDay(for: endDay)
        // Offsets counted back from today so the last point is always
        // today, whatever `days` is modulo the stride.
        let offsets = stride(from: 0, through: days, by: strideDays).reversed()
        return offsets.compactMap { offset -> TrendPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end),
                  let point = estimate(inputs: inputs(asOf: day, series: series,
                                                      profile: profile, calendar: calendar))
            else { return nil }
            return TrendPoint(date: day, biologicalAge: point.biologicalAge)
        }
    }

    // MARK: - Helpers

    static func median(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite).sorted()
        guard !finite.isEmpty else { return nil }
        let mid = finite.count / 2
        return finite.count.isMultiple(of: 2) ? (finite[mid - 1] + finite[mid]) / 2 : finite[mid]
    }

    /// Latest minus earliest weigh-in inside the window; nil with fewer
    /// than two.
    private static func weightDelta(_ entries: [DailyValue]) -> Double? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
        return last.value - first.value
    }

    /// `days` calendar days ending with the whole of `day`.
    private static func window(endingOn day: Date, days: Int, calendar: Calendar) -> Range<Date> {
        let startOfDay = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? startOfDay
        return start..<end
    }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func sortedByImpact(_ drivers: [Driver]) -> [Driver] {
        let order = Driver.Kind.allCases
        return drivers.sorted { lhs, rhs in
            let l = abs(lhs.deltaYears), r = abs(rhs.deltaYears)
            if l != r { return l > r }
            return (order.firstIndex(of: lhs.kind) ?? 0) < (order.firstIndex(of: rhs.kind) ?? 0)
        }
    }
}
