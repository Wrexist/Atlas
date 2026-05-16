import Foundation

/// Bio-age estimator. Pure function over a snapshot of the user's
/// biometrics — no HealthKit reads inside, so the math can be
/// exhaustively unit-tested without standing up a HealthKit
/// store.
///
/// **Not a medical-grade biomarker.** The output is an
/// "estimate based on your personal biometrics" — a directional
/// read on whether the user's HRV / RHR / sleep / weight are
/// pulling their effective age younger or older than their
/// chronological age. The UI must surface that hedge explicitly
/// (the "Available for users 18+" pill on Bevel's card is the
/// pattern).
///
/// Algorithm sketch:
///   1. Anchor at `chronologicalAge`.
///   2. Each present component contributes a signed delta in
///      years from a deterministic threshold table (see the
///      constants below).
///   3. Sum the deltas, cap total drift at ±`maxDriftYears` so a
///      single great-HRV week doesn't claim to roll back a
///      decade.
///   4. Compute confidence from input completeness +
///      sample-window length (a 7-day baseline carries less
///      weight than a 30-day one).
///   5. Below `minConfidence`, return nil. The UI shows the
///      "building baseline" / Pro-locked state instead of a
///      number it can't stand behind.
///
/// Cohort comparison (real percentile tables per age band) is a
/// v2 follow-up. Shipping without it keeps the legal surface
/// area small and gets the feature in front of users sooner;
/// adding cohort math later only refines the deltas, doesn't
/// restructure the algorithm.
enum PerformanceAgeEngine {

    // MARK: - Public types

    struct Inputs: Equatable, Sendable {
        let chronologicalAge: Int
        let hrvMedian30d: Double?
        let rhrMedian30d: Double?
        /// Median sleep hours (not efficiency) over the window.
        /// Efficiency would need stage data we don't reliably
        /// have; total time asleep is the lowest-friction proxy.
        let sleepHoursMedian30d: Double?
        let weightDeltaKg30d: Double?
        /// Days of HealthKit data backing the medians — drives
        /// confidence. The view layer asks HealthKit how many
        /// daily samples exist before passing this in.
        let healthDataDays: Int

        init(
            chronologicalAge: Int,
            hrvMedian30d: Double? = nil,
            rhrMedian30d: Double? = nil,
            sleepHoursMedian30d: Double? = nil,
            weightDeltaKg30d: Double? = nil,
            healthDataDays: Int = 0
        ) {
            self.chronologicalAge = chronologicalAge
            self.hrvMedian30d = hrvMedian30d
            self.rhrMedian30d = rhrMedian30d
            self.sleepHoursMedian30d = sleepHoursMedian30d
            self.weightDeltaKg30d = weightDeltaKg30d
            self.healthDataDays = healthDataDays
        }
    }

    struct Estimate: Equatable, Sendable {
        let biologicalAge: Double
        let confidence: Double
        let drivers: [Driver]
    }

    struct Driver: Equatable, Sendable, Identifiable {
        var id: String { kind.rawValue }
        let kind: Kind
        /// Signed delta in years this component contributed.
        /// Positive = older; negative = younger.
        let deltaYears: Double

        enum Kind: String, Sendable {
            case hrv, rhr, sleep, weight
        }
    }

    // MARK: - Algorithm constants

    /// Bound on total drift from chronological age. Real
    /// peer-reviewed bio-age estimators rarely exceed ±10 years
    /// for non-pathological populations; a tighter cap keeps the
    /// UI honest while we lack cohort tables.
    static let maxDriftYears: Double = 8.0

    /// Minimum confidence below which the engine returns nil and
    /// the UI surfaces the "building baseline" state. 0.6 maps
    /// roughly to "two of HRV / RHR / Sleep present, ≥14 days of
    /// data".
    static let minConfidence: Double = 0.6

    /// HRV thresholds in milliseconds. Above `hrvHighFloor` → up
    /// to `-hrvSwingYears`; below `hrvLowCeiling` → up to
    /// `+hrvSwingYears`. Linear interpolation between.
    static let hrvLowCeiling: Double = 25
    static let hrvHighFloor: Double = 60
    static let hrvSwingYears: Double = 2.5

    static let rhrAthleticCeiling: Double = 55      // ≤ this → up to -years
    static let rhrElevatedFloor: Double = 75        // ≥ this → up to +years
    static let rhrSwingYears: Double = 1.8

    static let sleepFloor: Double = 6.0             // ≤ this → +years
    static let sleepTarget: Double = 7.5            // ≥ this → 0 contribution
    static let sleepPenaltyYears: Double = 1.5

    /// Weight-trend signal. Either direction past the threshold
    /// counts as +0.5 years (rapid change in either direction
    /// stresses the system); slow drift is ignored.
    static let weightRapidDeltaKg: Double = 2.0
    static let weightTrendPenaltyYears: Double = 0.5

    // MARK: - Public

    static func estimate(inputs: Inputs) -> Estimate? {
        var drivers: [Driver] = []

        if let hrv = inputs.hrvMedian30d {
            drivers.append(.init(kind: .hrv, deltaYears: hrvContribution(hrv: hrv)))
        }
        if let rhr = inputs.rhrMedian30d {
            drivers.append(.init(kind: .rhr, deltaYears: rhrContribution(rhr: rhr)))
        }
        if let sleep = inputs.sleepHoursMedian30d {
            drivers.append(.init(kind: .sleep, deltaYears: sleepContribution(hours: sleep)))
        }
        if let weight = inputs.weightDeltaKg30d {
            drivers.append(.init(kind: .weight, deltaYears: weightContribution(deltaKg: weight)))
        }

        let confidence = confidenceScore(
            componentCount: drivers.count,
            healthDataDays: inputs.healthDataDays
        )
        guard confidence >= minConfidence else { return nil }

        let summedDelta = drivers.map(\.deltaYears).reduce(0, +)
        let cappedDelta = max(-maxDriftYears, min(maxDriftYears, summedDelta))
        let bioAge = Double(inputs.chronologicalAge) + cappedDelta

        // Sort drivers by absolute impact descending so the UI
        // can show "top 3 contributors" without re-sorting.
        let sortedDrivers = drivers.sorted { abs($0.deltaYears) > abs($1.deltaYears) }
        return Estimate(
            biologicalAge: bioAge,
            confidence: confidence,
            drivers: sortedDrivers
        )
    }

    // MARK: - Component contributions (testable in isolation)

    /// Maps HRV ms → signed years delta.
    ///   Above hrvHighFloor (60ms) → -hrvSwingYears (younger)
    ///   Below hrvLowCeiling (25ms) → +hrvSwingYears (older)
    ///   Linear interpolation between.
    static func hrvContribution(hrv: Double) -> Double {
        guard hrv > 0 else { return 0 }
        if hrv >= hrvHighFloor { return -hrvSwingYears }
        if hrv <= hrvLowCeiling { return hrvSwingYears }
        let normalized = (hrv - hrvLowCeiling) / (hrvHighFloor - hrvLowCeiling) // 0…1
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

    /// Sleep contribution. Below the floor we penalise; above
    /// target we don't reward — over-sleeping isn't a clean
    /// signal of being "younger" without more context. Between
    /// floor and target we scale the penalty linearly.
    static func sleepContribution(hours: Double) -> Double {
        guard hours > 0 else { return 0 }
        if hours >= sleepTarget { return 0 }
        if hours <= sleepFloor { return sleepPenaltyYears }
        let deficit = (sleepTarget - hours) / (sleepTarget - sleepFloor)
        return sleepPenaltyYears * deficit
    }

    /// Weight-trend contribution. Magnitude of change matters,
    /// not direction — rapid loss and rapid gain both stress
    /// the system. Slow drift below the threshold is ignored
    /// (a 0.5 kg shift over 30 days is noise).
    static func weightContribution(deltaKg: Double) -> Double {
        let magnitude = abs(deltaKg)
        return magnitude >= weightRapidDeltaKg ? weightTrendPenaltyYears : 0
    }

    /// Confidence scoring. Multiplies completeness (how many
    /// of HRV / RHR / Sleep / Weight inputs are present) by a
    /// data-density factor (more days of HealthKit history →
    /// more confidence in the medians).
    static func confidenceScore(componentCount: Int, healthDataDays: Int) -> Double {
        // 4 possible components; cap at 1.0.
        let completeness = min(1.0, Double(componentCount) / 4.0)
        // 30 days = full confidence; 7 days = 0.4; <7 = unusable.
        let densityFactor: Double
        if healthDataDays < 7 {
            densityFactor = 0
        } else if healthDataDays >= 30 {
            densityFactor = 1
        } else {
            densityFactor = 0.4 + Double(healthDataDays - 7) / 23 * 0.6
        }
        return completeness * densityFactor
    }
}
