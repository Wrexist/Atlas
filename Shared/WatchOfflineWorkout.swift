import Foundation

/// A strength workout the Watch runs by itself, started while the phone
/// was out of reach. The Workout page renders `snapshot` exactly as it
/// renders a phone-owned workout, and each tap goes through the same
/// `WatchWorkoutSnapshot.applying(_:at:)` the phone-owned flow uses for
/// its optimistic guess: here the guess is the record. Once finished it
/// travels to the phone, which files it as a `WorkoutSession` under the
/// same id.
struct WatchOfflineWorkout: Codable, Hashable, Identifiable, Sendable {
    private(set) var snapshot: WatchWorkoutSnapshot
    let routineID: UUID?
    let startedAt: Date
    /// Library id of each exercise row, keyed by the row's id.
    private(set) var exerciseIDs: [UUID: String]
    /// When each set was ticked off, keyed by set id.
    private(set) var completedAt: [UUID: Date]
    private(set) var finishedAt: Date?

    var id: UUID { snapshot.sessionId }

    /// Seeded from `routine`, or empty for a quick workout.
    init(routine: WatchRoutine?, at now: Date) {
        let rows = (routine?.lifts ?? []).map(Self.row(for:))
        snapshot = WatchWorkoutSnapshot(
            sessionId: UUID(),
            name: routine?.name ?? "",
            timerStartedAt: now,
            pausedElapsedSeconds: nil,
            exercises: rows.map(\.exercise),
            selectedExerciseID: rows.first?.exercise.id,
            rest: nil
        )
        routineID = routine?.id
        startedAt = now
        exerciseIDs = Dictionary(uniqueKeysWithValues: rows.map { ($0.exercise.id, $0.exerciseID) })
        completedAt = [:]
        finishedAt = nil
    }

    /// At least one working set logged: anything less isn't worth filing.
    var hasLoggedWork: Bool { snapshot.completedSets > 0 }

    /// Time spent paused. Each resume moves the clock's start forward by
    /// the pause, so the gap from the real start is the paused total.
    var pausedSeconds: TimeInterval {
        max(0, snapshot.timerStartedAt.timeIntervalSince(startedAt))
    }

    /// A tap on the Workout page. A finished workout takes no more taps.
    func applying(_ command: WatchWorkoutCommand, at now: Date) -> WatchOfflineWorkout {
        guard finishedAt == nil else { return self }
        var next = self
        next.snapshot = snapshot.applying(command, at: now)
        if case let .completeSet(exerciseID, setID, _, _) = command,
           !isCompleted(setID, in: exerciseID), next.isCompleted(setID, in: exerciseID) {
            next.completedAt[setID] = now
        }
        return next
    }

    /// Appends a lift and makes it the one logged next.
    func adding(_ lift: WatchLift) -> WatchOfflineWorkout {
        guard finishedAt == nil else { return self }
        var next = self
        let row = Self.row(for: lift)
        next.snapshot.exercises.append(row.exercise)
        next.snapshot.selectedExerciseID = row.exercise.id
        next.exerciseIDs[row.exercise.id] = row.exerciseID
        return next
    }

    /// Ends the workout at `now`. A pause still running counts as paused
    /// time, and a rest still running ends with it.
    func finished(at now: Date) -> WatchOfflineWorkout {
        guard finishedAt == nil else { return self }
        var next = applying(.setPaused(false), at: now)
        next.snapshot.rest = nil
        next.finishedAt = now
        return next
    }

    private func isCompleted(_ setID: UUID, in exerciseID: UUID) -> Bool {
        snapshot.exercises.first { $0.id == exerciseID }?
            .sets.first { $0.id == setID }?.completed ?? false
    }

    private static func row(for lift: WatchLift) -> (exercise: WatchWorkoutSnapshot.Exercise, exerciseID: String) {
        let sets = (1...max(1, lift.sets)).map { index in
            WatchWorkoutSnapshot.SetRow(
                id: UUID(), index: index, weightKg: lift.weightKg, reps: lift.reps,
                completed: false, isWarmup: false, logsReps: true
            )
        }
        let exercise = WatchWorkoutSnapshot.Exercise(id: UUID(), name: lift.name, restSeconds: lift.restSeconds, sets: sets)
        return (exercise, lift.exerciseID)
    }
}

/// The Watch's outbox of finished workouts and the phone's receipts for
/// them. A workout leaves the outbox only once a phone push lists its id,
/// so one the phone received but failed to save is sent again; the phone
/// files each id once, however many copies arrive.
enum WatchOfflineSyncEngine {
    /// Receipts the phone keeps on the wire. A receipt that falls off
    /// before the Watch saw it costs one resend, which the phone answers
    /// with a fresh receipt without filing the workout twice.
    static let receiptLimit = 30

    /// Adds a finished workout with logged work, once.
    static func enqueue(_ workout: WatchOfflineWorkout, into outbox: [WatchOfflineWorkout]) -> [WatchOfflineWorkout] {
        guard workout.finishedAt != nil, workout.hasLoggedWork,
              !outbox.contains(where: { $0.id == workout.id }) else { return outbox }
        return outbox + [workout]
    }

    /// The outbox without the workouts the phone has filed.
    static func pruned(_ outbox: [WatchOfflineWorkout], syncedIDs: [UUID]) -> [WatchOfflineWorkout] {
        let synced = Set(syncedIDs)
        return outbox.filter { !synced.contains($0.id) }
    }

    /// What to hand WatchConnectivity: the outbox minus the copies it is
    /// still delivering, so a relaunch doesn't stack duplicate transfers.
    static func toSend(_ outbox: [WatchOfflineWorkout], inFlight: Set<UUID>) -> [WatchOfflineWorkout] {
        outbox.filter { !inFlight.contains($0.id) }
    }

    /// The phone's receipts with `id` added, newest last, capped.
    static func recordingReceipt(_ id: UUID, in receipts: [UUID]) -> [UUID] {
        guard !receipts.contains(id) else { return receipts }
        return Array((receipts + [id]).suffix(receiptLimit))
    }

    static func message(for workout: WatchOfflineWorkout) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(workout) else { return nil }
        return [
            "action": WatchMessage.offlineWorkout,
            WatchMessage.offlineWorkoutKey: data,
            WatchMessage.offlineWorkoutIdKey: workout.id.uuidString,
        ]
    }

    static func workoutID(in message: [String: Any]) -> UUID? {
        guard message["action"] as? String == WatchMessage.offlineWorkout else { return nil }
        return (message[WatchMessage.offlineWorkoutIdKey] as? String).flatMap(UUID.init(uuidString:))
    }

    static func workout(in message: [String: Any]) -> WatchOfflineWorkout? {
        guard message["action"] as? String == WatchMessage.offlineWorkout,
              let data = message[WatchMessage.offlineWorkoutKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchOfflineWorkout.self, from: data)
    }
}
