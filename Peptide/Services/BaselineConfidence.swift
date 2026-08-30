import Foundation

/// Shared three-tier read on how much personal history Atlas actually has
/// for a given metric — reused by every personal-baseline computation
/// instead of each engine inventing its own ad hoc sample-count gate.
///
/// Before this type, "do we trust this yet" was answered independently
/// (and inconsistently) in several places: `HealthRangeService` used a
/// binary 7-day gate (nothing below it, full trust above it, no middle
/// ground), `PerformanceAgeEngine` used its own data-density-days concept,
/// and `StackRecommendationEngine` used a signal count — none of them
/// shared a vocabulary, and none of them distinguished "just barely
/// enough data" from "months of consistent history." Personalization
/// brief Phase 3 is explicit that those two cases must not look equally
/// reliable, so this type exists to be the one shared answer.
///
/// Deliberately just three tiers, not a continuous confidence score — a
/// fake-precision "73% confident" number would invite exactly the kind of
/// simulated intelligence the brief warns against (Phase 19). Three tiers
/// is enough to gate behavior (never compare below insufficient; hedge
/// the copy at emerging; speak plainly at established) without pretending
/// to a precision Atlas doesn't have.
enum BaselineConfidence: Int, Comparable, Sendable, Equatable {
    /// Not enough history to say anything personal yet. Callers must not
    /// show a personal comparison at this tier — general guidance only.
    case insufficientHistory
    /// Some personal history exists, but not enough to fully trust a
    /// comparison. Personal language is fine here, but should be hedged
    /// ("early read", "still learning") rather than stated flatly.
    case emergingBaseline
    /// Enough consistent history that a personal comparison doesn't need
    /// hedging.
    case establishedBaseline

    static func < (lhs: BaselineConfidence, rhs: BaselineConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// `emergingAt` and `establishedAt` are sample-count thresholds the
    /// caller supplies for its own domain — e.g. `HealthRangeService`
    /// counts days of biometric samples, `TrainingPatternEngine` counts
    /// completed weeks of training history. There is deliberately no
    /// single hardcoded threshold here: "enough HRV history" and "enough
    /// training-frequency history" are different sample sizes, and a
    /// shared numeric bar would be exactly the kind of invented baseline
    /// Phase 2 of the personalization brief warns against.
    ///
    /// `sampleCount` at or above `establishedAt` → established;
    /// at or above `emergingAt` (but below `establishedAt`) → emerging;
    /// below `emergingAt` → insufficient.
    static func evaluate(sampleCount: Int, emergingAt: Int, establishedAt: Int) -> BaselineConfidence {
        assert(emergingAt <= establishedAt, "emergingAt must not exceed establishedAt")
        if sampleCount >= establishedAt { return .establishedBaseline }
        if sampleCount >= emergingAt { return .emergingBaseline }
        return .insufficientHistory
    }
}
