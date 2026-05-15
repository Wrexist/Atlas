import Foundation

/// Best-ever record per exercise, computed from the user's workout
/// history. Cached separately from session storage so the PR badges on
/// the Train tab don't require a full history scan on every render.
/// Refreshed by `PRDetectionEngine` on workout finish.
struct PersonalRecord: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// `Exercise.id` or `CustomExercise.id`. One PR record per
    /// exercise; the engine upserts by id.
    var exerciseID: String
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

    init(
        id: UUID = UUID(),
        exerciseID: String,
        bestEstimatedOneRepMaxKg: Double? = nil,
        bestEstimatedOneRepMaxAt: Date? = nil,
        bestAbsoluteWeightKg: Double? = nil,
        bestAbsoluteWeightAt: Date? = nil,
        bestSessionVolumeKg: Double? = nil,
        bestSessionVolumeAt: Date? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
        self.bestEstimatedOneRepMaxAt = bestEstimatedOneRepMaxAt
        self.bestAbsoluteWeightKg = bestAbsoluteWeightKg
        self.bestAbsoluteWeightAt = bestAbsoluteWeightAt
        self.bestSessionVolumeKg = bestSessionVolumeKg
        self.bestSessionVolumeAt = bestSessionVolumeAt
    }
}
