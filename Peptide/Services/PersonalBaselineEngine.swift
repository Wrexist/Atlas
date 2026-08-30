import Foundation

/// Generalizes the percentile/spread math `HealthRangeService` already
/// uses for HRV/RHR/sleep into a reusable, domain-agnostic personal
/// baseline — so a new personalization surface (training frequency,
/// workout volume, or anything else expressed as a numeric history) gets
/// the same "your own normal, not a population number" treatment without
/// re-deriving percentile code a third or fourth time.
///
/// Bundles the personal-range stats together with a `BaselineConfidence`
/// tier computed from the caller's own domain-appropriate thresholds —
/// see `BaselineConfidence` for why those thresholds are caller-supplied
/// rather than fixed here.
///
/// Pure function: no I/O, no singletons, no HealthKit/SwiftData
/// dependency. Callers gather the raw history themselves.
enum PersonalBaselineEngine {

    struct Baseline: Equatable, Sendable {
        let mean: Double
        let median: Double
        /// Population standard deviation (not Bessel-corrected) —
        /// consistent with treating this history as the complete record
        /// of what's normal for this user so far, not a sample estimating
        /// some larger population.
        let standardDeviation: Double
        let p10: Double
        let p25: Double
        let p75: Double
        let p90: Double
        let sampleCount: Int
        let confidence: BaselineConfidence
    }

    /// Builds a baseline from a value history. Returns `nil` only when
    /// `values` is empty — a single data point still produces a (very
    /// low-confidence) baseline rather than `nil`, so callers can tell
    /// "never measured" apart from "measured once."
    static func build(
        values: [Double],
        emergingAt: Int,
        establishedAt: Int
    ) -> Baseline? {
        guard !values.isEmpty else { return nil }
        let count = values.count
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count)

        return Baseline(
            mean: mean,
            median: percentile(sorted, 0.5),
            standardDeviation: variance.squareRoot(),
            p10: percentile(sorted, 0.10),
            p25: percentile(sorted, 0.25),
            p75: percentile(sorted, 0.75),
            p90: percentile(sorted, 0.90),
            sampleCount: count,
            confidence: BaselineConfidence.evaluate(
                sampleCount: count,
                emergingAt: emergingAt,
                establishedAt: establishedAt
            )
        )
    }

    /// Nearest-rank percentile — no interpolation, so results always land
    /// on an actual observed value rather than an interpolated point
    /// between two of them. Stable for the small samples (single-digit to
    /// low-double-digit counts) personalization baselines typically work
    /// with. Identical formula to `HealthRangeService`'s original
    /// percentile helper, which now forwards here.
    static func percentile(_ sortedValues: [Double], _ p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let rank = max(1, min(sortedValues.count, Int((p * Double(sortedValues.count)).rounded(.up))))
        return sortedValues[rank - 1]
    }
}
