import Foundation

/// Best-ever record per exercise, computed from the user's workout
/// history. Cached separately from session storage so the PR badges on
/// the Train tab don't require a full history scan on every render.
/// Refreshed by `PRDetectionEngine` on workout finish.
///
/// `exerciseID` is the natural primary key — exactly one record per
/// exercise — so we use it for `Identifiable`. There is no separate
/// UUID id: a synthetic id would be lost on every round-trip through
/// `StoredPersonalRecord` (which keys by `exerciseID`) and silently
/// break SwiftUI list diffing.
struct PersonalRecord: Codable, Hashable, Identifiable, Sendable {
    /// `Exercise.id` or `CustomExercise.id`. One PR record per
    /// exercise; the engine upserts by id.
    var exerciseID: String

    /// `Identifiable` conformance — keyed by the exercise id so SwiftUI
    /// list diffing stays stable across saves and the engine's
    /// upsert-by-exerciseID semantics carry through to the view layer.
    var id: String { exerciseID }
    /// Best single-set estimated 1RM in kg (Epley formula). Nil when
    /// the exercise has never been logged with a weight + rep.
    var bestEstimatedOneRepMaxKg: Double?
    /// Date the best e1RM was achieved. Useful for the "PR set 14 days
    /// ago" subtitle on the Train tab hero.
    var bestEstimatedOneRepMaxAt: Date?
    /// Best single-set absolute weight in kg, regardless of reps.
    /// Tracked separately from e1RM because a 1-rep PR and a 10-rep PR
    /// are different milestones to the user.
    var bestAbsoluteWeightKg: Double?
    var bestAbsoluteWeightAt: Date?
    /// Best total volume (sum of `weight * reps` across all working
    /// sets) for this exercise in a single session. Drives "you moved
    /// more weight than last time" callouts.
    var bestSessionVolumeKg: Double?
    var bestSessionVolumeAt: Date?
    /// Best single-set rep count for bodyweight exercises (weightKg
    /// == 0). Tracked separately so push-ups, pull-ups, and other
    /// no-load lifts can produce PRs — previously every weight-0 set
    /// failed the `bestE1RM > 0` and `bestAbs > 0` guards and
    /// bodyweight-only users saw no PRs forever (audit Train H3).
    var bestRepsBodyweight: Int?
    var bestRepsBodyweightAt: Date?

    init(
        exerciseID: String,
        bestEstimatedOneRepMaxKg: Double? = nil,
        bestEstimatedOneRepMaxAt: Date? = nil,
        bestAbsoluteWeightKg: Double? = nil,
        bestAbsoluteWeightAt: Date? = nil,
        bestSessionVolumeKg: Double? = nil,
        bestSessionVolumeAt: Date? = nil,
        bestRepsBodyweight: Int? = nil,
        bestRepsBodyweightAt: Date? = nil
    ) {
        self.exerciseID = exerciseID
        self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
        self.bestEstimatedOneRepMaxAt = bestEstimatedOneRepMaxAt
        self.bestAbsoluteWeightKg = bestAbsoluteWeightKg
        self.bestAbsoluteWeightAt = bestAbsoluteWeightAt
        self.bestSessionVolumeKg = bestSessionVolumeKg
        self.bestSessionVolumeAt = bestSessionVolumeAt
        self.bestRepsBodyweight = bestRepsBodyweight
        self.bestRepsBodyweightAt = bestRepsBodyweightAt
    }
}
