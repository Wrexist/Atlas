import Foundation

/// The in-progress workout as the Watch renders and logs it. Built on the
/// phone by `WatchWorkoutSnapshotBuilder` from the active `WorkoutSession`,
/// which stays the only source of truth: the Watch sends a
/// `WatchWorkoutRequest`, shows its guess straight away through
/// `applying(_:at:)`, and adopts the phone's next push.
///
/// Weights stay in canonical kilograms, the contract `SetEntry` keeps;
/// the Watch converts for display against `WatchData.measurementUnit`.
struct WatchWorkoutSnapshot: Codable, Hashable, Sendable {
    struct Exercise: Codable, Hashable, Identifiable, Sendable {
        /// `WorkoutExerciseEntry.id`, not the library id, so the same
        /// exercise twice in one workout stays two rows.
        let id: UUID
        let name: String
        /// Rest after a working set, resolved phone-side from the
        /// exercise's override or the user's default. Zero means no rest.
        let restSeconds: Int
        var sets: [SetRow]

        var workingSets: [SetRow] { sets.filter { !$0.isWarmup } }
        var completedWorkingSets: Int { workingSets.filter(\.completed).count }
    }

    struct SetRow: Codable, Hashable, Identifiable, Sendable {
        let id: UUID
        let index: Int
        var weightKg: Double
        var reps: Int
        var completed: Bool
        let isWarmup: Bool
        /// False for timed and distance sets: the Watch ticks them off but
        /// has no reps or load to edit, matching `SetEntry.supportsRepLogging`.
        let logsReps: Bool
    }

    struct Rest: Codable, Hashable, Sendable {
        var endsAt: Date
        var totalSeconds: Double
        let sourceExerciseID: UUID
        let targetExerciseID: UUID
        let targetSetID: UUID
    }

    let sessionId: UUID
    /// Display name, or "" for an unnamed workout.
    let name: String
    /// Start shifted forward by the time spent paused, so a timer counting
    /// up from here shows active time only.
    var timerStartedAt: Date
    /// Frozen active seconds while paused; nil while the clock runs.
    var pausedElapsedSeconds: Int?
    var exercises: [Exercise]
    var selectedExerciseID: UUID?
    /// Nil while paused, like the Live Activity: a frozen countdown has no
    /// end date to count toward.
    var rest: Rest?

    var isPaused: Bool { pausedElapsedSeconds != nil }

    var completedSets: Int { exercises.reduce(0) { $0 + $1.completedWorkingSets } }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.workingSets.count } }

    func isResting(at now: Date) -> Bool {
        guard let rest, !isPaused else { return false }
        return rest.endsAt > now
    }

    var selectedExercise: Exercise? {
        exercises.first { $0.id == selectedExerciseID }
            ?? exercises.first { $0.sets.contains { !$0.completed } }
            ?? exercises.first
    }

    /// The set the user is about to do: the one the rest leads to, else
    /// the next open set of the selected exercise (warm-ups included, in
    /// order), else the first open set anywhere.
    var upNext: (exercise: Exercise, set: SetRow)? {
        if let rest,
           let exercise = exercises.first(where: { $0.id == rest.targetExerciseID }),
           let set = exercise.sets.first(where: { $0.id == rest.targetSetID && !$0.completed }) {
            return (exercise, set)
        }
        let ordered = [selectedExercise].compactMap { $0 } + exercises
        for exercise in ordered {
            if let set = exercise.sets.first(where: { !$0.completed }) { return (exercise, set) }
        }
        return nil
    }

    /// The Watch's guess at the phone's answer, so a tap shows at once even
    /// when the phone is out of reach. Mirrors `WorkoutSessionService`;
    /// anything it can't predict waits for the phone's next push.
    func applying(_ command: WatchWorkoutCommand, at now: Date) -> WatchWorkoutSnapshot {
        var next = self
        switch command {
        case let .completeSet(exerciseID, setID, weightKg, reps):
            next.complete(setID: setID, in: exerciseID, weightKg: weightKg, reps: reps, at: now)
        case .skipRest:
            next.skipRest()
        case let .extendRest(seconds):
            guard var rest = next.rest else { break }
            let remaining = max(0, rest.endsAt.timeIntervalSince(now) + Double(seconds))
            guard remaining > 0 else { next.skipRest(); break }
            rest.endsAt = now.addingTimeInterval(remaining)
            rest.totalSeconds = remaining
            next.rest = rest
        case let .selectExercise(exerciseID):
            if exercises.contains(where: { $0.id == exerciseID }) { next.selectedExerciseID = exerciseID }
        case let .addSet(exerciseID, setID):
            guard let index = next.exercises.firstIndex(where: { $0.id == exerciseID }) else { break }
            let previous = next.exercises[index].sets.last
            next.exercises[index].sets.append(SetRow(
                id: setID,
                index: (previous?.index ?? 0) + 1,
                weightKg: previous?.weightKg ?? 0,
                reps: previous?.reps ?? 8,
                completed: false,
                isWarmup: false,
                logsReps: previous?.logsReps ?? true
            ))
            next.selectedExerciseID = exerciseID
        case let .setPaused(paused):
            guard paused != isPaused else { break }
            if paused {
                next.pausedElapsedSeconds = max(0, Int(now.timeIntervalSince(timerStartedAt)))
                next.rest = nil
            } else {
                next.timerStartedAt = now.addingTimeInterval(-Double(pausedElapsedSeconds ?? 0))
                next.pausedElapsedSeconds = nil
            }
        }
        return next
    }

    private mutating func complete(setID: UUID, in exerciseID: UUID, weightKg: Double, reps: Int, at now: Date) {
        guard !isPaused,
              let e = exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setID }),
              !exercises[e].sets[s].completed else { return }
        if exercises[e].sets[s].logsReps {
            exercises[e].sets[s].weightKg = weightKg
            exercises[e].sets[s].reps = reps
        }
        exercises[e].sets[s].completed = true
        selectedExerciseID = exerciseID
        guard !exercises[e].sets[s].isWarmup else { return }
        rest = nil
        let seconds = exercises[e].restSeconds
        if seconds > 0, let target = nextPendingWorkingSet(preferring: exerciseID) {
            rest = Rest(
                endsAt: now.addingTimeInterval(Double(seconds)),
                totalSeconds: Double(seconds),
                sourceExerciseID: exerciseID,
                targetExerciseID: target.exercise,
                targetSetID: target.set
            )
        }
    }

    private mutating func skipRest() {
        guard let rest else { return }
        if selectedExercise?.id == rest.sourceExerciseID { selectedExerciseID = rest.targetExerciseID }
        self.rest = nil
    }

    /// `WorkoutSession.nextPendingSet(after:)` over the snapshot. Exercises
    /// arrive in display order, so no sort is needed here.
    private func nextPendingWorkingSet(preferring exerciseID: UUID) -> (exercise: UUID, set: UUID)? {
        let preferred = exercises.filter { $0.id == exerciseID } + exercises.filter { $0.id != exerciseID }
        for exercise in preferred {
            if let set = exercise.sets.first(where: { !$0.completed && !$0.isWarmup }) {
                return (exercise.id, set.id)
            }
        }
        return nil
    }
}

/// What the Watch can ask of the active workout. Each case maps onto one
/// existing `WorkoutSessionService` mutation, so the wrist logs a set
/// exactly as checking it off on the phone does.
enum WatchWorkoutCommand: Codable, Equatable, Sendable {
    case completeSet(exerciseID: UUID, setID: UUID, weightKg: Double, reps: Int)
    case skipRest
    case extendRest(seconds: Int)
    case selectExercise(exerciseID: UUID)
    /// The Watch picks the new set's id so it can be logged before the
    /// phone answers, and the phone's copy keeps the same id.
    case addSet(exerciseID: UUID, setID: UUID)
    /// Absolute rather than a toggle, so a message delivered twice can't
    /// undo itself.
    case setPaused(Bool)
}

/// A command bound to the workout it was issued against. The phone drops
/// a request whose session has since finished or been replaced, so a tap
/// delivered late can't land in the next workout.
struct WatchWorkoutRequest: Codable, Equatable, Sendable {
    let sessionId: UUID
    let command: WatchWorkoutCommand
    /// When the user tapped. A set completed while the phone was out of
    /// reach starts its rest from the tap, not from delivery.
    let issuedAt: Date

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> WatchWorkoutRequest? {
        try? JSONDecoder().decode(WatchWorkoutRequest.self, from: data)
    }
}

/// Training glance for the Watch complication when no workout is running.
struct WatchTrainingSnapshot: Codable, Hashable, Sendable {
    let workoutsThisWeek: Int
    let lastWorkout: WidgetWorkoutSummary?
}
