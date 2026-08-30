import Foundation

/// User-defined workout template. A `Routine` is the *shell* — exercise
/// list with target set schemes — from which a `WorkoutSession` is
/// instantiated when the user taps Start. The session is the concrete
/// log; the routine is the plan.
///
/// Bundled programs (PPL, 5/3/1, etc.) also reduce to a collection of
/// routines under the hood — a `Program` is just a sequence of
/// `RoutineTemplate`s with scheduling on top.
struct Routine: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// Optional brief — e.g. "Push day, intermediate". Surfaces under
    /// the title on the routine list and editor.
    var subtitle: String?
    var exercises: [RoutineExercise]
    /// Default rest seconds for this routine — overridden per-exercise
    /// by `RoutineExercise.restSeconds`. Falls back to
    /// `TrainingPreferences.restTimerDefault` when nil.
    var defaultRestSeconds: Int?
    /// Last time the user edited this routine. Breaks ties on
    /// `sortIndex` so an untouched library still reads
    /// most-recently-edited first.
    var updatedAt: Date
    /// Drag-to-reorder sort key; smaller values sort first.
    ///
    /// Optional rather than a defaulted `Int` because `Routine` is
    /// `Codable` and rides the backup archive: a synthesized decoder
    /// treats a missing key as an error, so a non-optional field here
    /// would fail the import of every backup written before routines
    /// became user-orderable. Nil means "never reordered", which sorts
    /// as 0 — the order the list had before this key existed.
    var sortIndex: Int?

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        exercises: [RoutineExercise] = [],
        defaultRestSeconds: Int? = nil,
        updatedAt: Date = Date(),
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.exercises = exercises
        self.defaultRestSeconds = defaultRestSeconds
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
    }
}

/// One exercise slot inside a routine. The set scheme is a *target*,
/// not a log — the user's actual sets land on `SetEntry` once the
/// session is instantiated.
struct RoutineExercise: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// `Exercise.id` or `CustomExercise.id`.
    var exerciseID: String
    /// Order within the routine. Drives drag-to-reorder.
    var index: Int
    /// Target sets × reps. e.g. `targetSets = 5, targetReps = 5` for
    /// StrongLifts. The active-workout screen seeds this many empty
    /// `SetEntry` rows on session start.
    var targetSets: Int
    var targetReps: Int
    /// Optional target RPE — drives the "@RPE 8" badge.
    var targetRPE: Double?
    /// Optional percentage of 1RM for percentage-based programs
    /// (5/3/1, nSuns). When set, the active-workout screen pre-fills
    /// weight from the user's `PersonalRecord.bestEstimatedOneRepMaxKg`.
    var targetPercentOf1RM: Double?
    /// Per-exercise rest override. Nil → falls back to the routine's
    /// `defaultRestSeconds`.
    var restSeconds: Int?
    /// Optional note attached to this slot, e.g. "tempo 3-1-1".
    var note: String?

    init(
        id: UUID = UUID(),
        exerciseID: String,
        index: Int,
        targetSets: Int = 3,
        targetReps: Int = 10,
        targetRPE: Double? = nil,
        targetPercentOf1RM: Double? = nil,
        restSeconds: Int? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.index = index
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetRPE = targetRPE
        self.targetPercentOf1RM = targetPercentOf1RM
        self.restSeconds = restSeconds
        self.note = note
    }
}
