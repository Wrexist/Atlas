import Foundation

/// Conservative "what changed" classifier — personalization brief Phase 8.
/// Deliberately narrow: given a personal baseline (see
/// `PersonalBaselineEngine`) and today's value, decides whether today is
/// genuinely notable relative to what's normal *for this user*, using a
/// threshold that scales with that user's own variability (a standard-
/// deviation multiple) rather than a fixed absolute cutoff that would
/// flag completely different things as "notable" for a low-variance user
/// versus a high-variance one.
///
/// Never classifies below `.emergingBaseline` confidence — the brief asks
/// to "avoid reacting to normal noise," and the noisiest possible case is
/// treating a single data point as though it were an established pattern.
enum ChangeDetectionEngine {

    enum Change: Equatable, Sendable {
        case stable
        /// Meaningfully above the personal baseline's mean, but still
        /// within the p10–p90 spread of what's happened before.
        case notablyHigher
        /// Meaningfully below the mean, same caveat.
        case notablyLower
        /// Outside the p10–p90 band entirely — beyond anything this
        /// specific user's own recent history has shown, regardless of
        /// direction.
        case unusual
    }

    struct Result: Equatable, Sendable {
        let change: Change
        let confidence: BaselineConfidence
    }

    /// `minMeaningfulDeltaInStandardDeviations`: how many standard
    /// deviations away from the mean counts as "notable." 1.0 is a
    /// reasonable conservative default; callers may tune it per metric.
    ///
    /// Returns `nil` when the baseline's confidence is
    /// `.insufficientHistory` — callers must have a real fallback
    /// (generic copy, no comparison) for that case rather than this
    /// engine forcing a verdict it can't back up.
    static func evaluate(
        current: Double,
        against baseline: PersonalBaselineEngine.Baseline,
        minMeaningfulDeltaInStandardDeviations: Double = 1.0
    ) -> Result? {
        guard baseline.confidence > .insufficientHistory else { return nil }

        if current < baseline.p10 || current > baseline.p90 {
            return Result(change: .unusual, confidence: baseline.confidence)
        }

        guard baseline.standardDeviation > 0 else {
            // Every historical value was identical — any current value
            // that still lands inside the p10–p90 band (necessarily the
            // same single value) is stable by definition; a value outside
            // it was already caught above.
            return Result(change: .stable, confidence: baseline.confidence)
        }

        let deviations = (current - baseline.mean) / baseline.standardDeviation
        if deviations >= minMeaningfulDeltaInStandardDeviations {
            return Result(change: .notablyHigher, confidence: baseline.confidence)
        }
        if deviations <= -minMeaningfulDeltaInStandardDeviations {
            return Result(change: .notablyLower, confidence: baseline.confidence)
        }
        return Result(change: .stable, confidence: baseline.confidence)
    }
}
