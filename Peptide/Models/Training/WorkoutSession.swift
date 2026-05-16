import Foundation

/// One exercise within a `WorkoutSession`. Holds the foreign key into
/// the exercise library plus the set list. The exercise itself isn't
/// embedded — the library is a single source of truth and the JSON
/// blob would grow without bound if we duplicated instructions and
/// images on every session.
struct WorkoutExerciseEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// `Exercise.id` from the bundled library, or `CustomExercise.id`
    /// for a user-created exercise. Resolved against
    /// `ExerciseLibrary.lookup(id:)` at read time.
    var exerciseID: String
    /// Position within the parent session — drives display order.
    var index: Int
    var sets: [SetEntry]
    /// Per-exercise note (e.g. "switch to wide grip next week"). Caps
    /// at ~280 chars in the UI.
    var note: String?
    /// User-configured rest seconds between sets for this exercise.
    /// Defaults to `TrainingPreferences.restTimerDefault` when nil so
    /// the timer can flex per-exercise without per-set rows getting
    /// noisy.
    var restSeconds: Int?
    /// IDs of other exercise entries in the same session that share a
    /// superset with this one. Empty for standalone exercises. A
    /// superset is a symmetric relation, encoded redundantly on both
    /// sides so look-up at render time is a single property access.
    var supersetGroup: UUID?

    init(
        id: UUID = UUID(),
        exerciseID: String,
        index: Int,
        sets: [SetEntry] = [],
        note: String? = nil,
        restSeconds: Int? = nil,
        supersetGroup: UUID? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.index = index
        self.sets = sets
        self.note = note
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
    }

    /// Working-set volume for this exercise (warm-ups + incomplete sets
    /// excluded). Drives the per-exercise volume row on the finish
    /// screen.
    var workingVolumeKg: Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }

    /// Top working set's estimated 1RM, used for PR detection. Returns
    /// `nil` when no set is eligible.
    var topEstimatedOneRepMaxKg: Double? {
        sets.compactMap(\.estimatedOneRepMaxKg).max()
    }
}

/// One workout — the canonical unit of training. Created when the user
/// taps Start on a routine (or "Empty workout"); receives sets as the
/// user checks them off; sealed on Finish, which also writes an
/// `HKWorkout` sample when HealthKit is wired (deferred to a later
/// commit).
///
/// Persisted as a SwiftData `@Model` via `StoredWorkoutSession` —
/// the value type is the in-memory shape passed around by services
/// and views; the `@Model` is the on-disk shell that JSON-encodes
/// the `exercises` array.
struct WorkoutSession: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// Optional display name. Defaults to the routine name when one is
    /// active, otherwise nil (the UI shows "Workout · Mon May 15").
    var name: String?
    /// Foreign key into the user's routine library when this session
    /// was started from a saved template. Nil for empty workouts.
    var routineID: UUID?
    /// Foreign key into `Program` when the session is the next day of
    /// an active program. Nil otherwise.
    var programID: UUID?
    /// Wall-clock start time. Drives the calendar dot and the in-app
    /// elapsed-timer fallback when scenePhase background-restoration
    /// can't trust an Activity timestamp.
    var startedAt: Date
    /// Set on Finish. Nil while the workout is active; presence of a
    /// finishedAt is the source of truth for "is this still in
    /// progress?".
    var finishedAt: Date?
    var exercises: [WorkoutExerciseEntry]
    /// Free-form per-session note. Optional.
    var note: String?
    /// User's "How did it go?" rating 1–5, captured on the finish
    /// screen. Optional.
    var perceivedEffort: Int?

    init(
        id: UUID = UUID(),
        name: String? = nil,
        routineID: UUID? = nil,
        programID: UUID? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        exercises: [WorkoutExerciseEntry] = [],
        note: String? = nil,
        perceivedEffort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.routineID = routineID
        self.programID = programID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exercises = exercises
        self.note = note
        self.perceivedEffort = perceivedEffort
    }

    /// `true` while the user is mid-workout — exactly one session per
    /// user should ever be in this state. `WorkoutSessionService`
    /// enforces the invariant on start.
    var isActive: Bool { finishedAt == nil }

    /// Total elapsed seconds. Snapshots wall-clock against `Date()`
    /// while active so the UI can render a live duration without the
    /// service pumping a publisher.
    func elapsedSeconds(now: Date = Date()) -> Int {
        let end = finishedAt ?? now
        return max(0, Int(end.timeIntervalSince(startedAt)))
    }

    /// Total working volume across every exercise, in kilograms. Drives
    /// the finish-screen hero stat and the weekly Insights chart.
    var totalVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.workingVolumeKg }
    }

    /// Total completed working sets — warm-ups and unchecked sets
    /// excluded. Drives the "X sets" pill on the history row.
    var completedSetCount: Int {
        exercises.reduce(0) { acc, ex in
            acc + ex.sets.filter { $0.completed && !$0.isWarmup }.count
        }
    }
}
