import Foundation

/// Turns a workout the Watch ran on its own into the `WorkoutSession` the
/// phone files, under the Watch's id so a second delivery finds it. Rows,
/// sets and their ids carry over; weights and reps are clamped like any
/// manual entry. Pure, so the mapping is pinned without a paired watch.
enum WatchWorkoutImportEngine {
    /// Nil for a workout that isn't finished or logged no working set:
    /// the phone's own finish refuses those too.
    static func session(from workout: WatchOfflineWorkout) -> WorkoutSession? {
        guard let finishedAt = workout.finishedAt, workout.hasLoggedWork else { return nil }
        let snapshot = workout.snapshot
        let exercises = snapshot.exercises.compactMap { exercise in
            workout.exerciseIDs[exercise.id].map { (row: exercise, libraryID: $0) }
        }
        return WorkoutSession(
            id: workout.id,
            name: snapshot.name.isEmpty ? nil : snapshot.name,
            routineID: workout.routineID,
            startedAt: workout.startedAt,
            finishedAt: finishedAt,
            exercises: exercises.enumerated().map { position, pair in
                let exercise = pair.row
                return WorkoutExerciseEntry(
                    id: exercise.id,
                    exerciseID: pair.libraryID,
                    index: position,
                    sets: exercise.sets.map { setEntry(from: $0, completedAt: workout.completedAt[$0.id]) },
                    restSeconds: exercise.restSeconds
                )
            },
            focus: WorkoutFocusState(timing: .tracked, pausedSeconds: workout.pausedSeconds)
        )
    }

    private static func setEntry(from row: WatchWorkoutSnapshot.SetRow, completedAt: Date?) -> SetEntry {
        SetEntry(
            id: row.id,
            index: row.index,
            weightKg: SetEntryLimits.clampWeightKg(row.weightKg),
            reps: SetEntryLimits.clampReps(row.reps),
            completed: row.completed,
            isWarmup: row.isWarmup,
            completedAt: row.completed ? completedAt : nil,
            measurement: measurement(from: row.measurement)
        )
    }

    /// Nil for a plain loaded set, or a kind this build doesn't know: a
    /// newer Watch's measurement is better dropped than guessed.
    private static func measurement(from wire: WatchSetMeasurement?) -> SetEntry.Measurement? {
        guard let wire, let kind = SetEntry.Measurement.Kind(rawValue: wire.kind) else { return nil }
        return SetEntry.Measurement(kind: kind, load: SetEntry.Measurement.Load(rawValue: wire.load) ?? .recorded)
    }
}
