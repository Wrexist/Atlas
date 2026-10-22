import Foundation

/// Flattens the active `WorkoutSession` into what the Watch renders. Pure,
/// like `WidgetSnapshotBuilder`, so the tests pin the mapping without a
/// paired watch. Main-actor because exercise names come from
/// `ExerciseLibrary`.
@MainActor
enum WatchWorkoutSnapshotBuilder {
    static func snapshot(of session: WorkoutSession?, defaultRestSeconds: Int) -> WatchWorkoutSnapshot? {
        guard let session, session.isActive else { return nil }
        let rest = session.isPaused ? nil : session.focus?.rest
        return WatchWorkoutSnapshot(
            sessionId: session.id,
            name: session.name ?? "",
            timerStartedAt: session.startedAt.addingTimeInterval(session.focus?.pausedSeconds ?? 0),
            pausedElapsedSeconds: session.isPaused ? session.elapsedSeconds() : nil,
            exercises: session.exercises.sorted { $0.index < $1.index }.map { entry in
                exercise(entry, defaultRestSeconds: defaultRestSeconds)
            },
            selectedExerciseID: session.selectedExercise?.id,
            rest: rest.flatMap { rest in
                rest.endsAt.map { endsAt in
                    WatchWorkoutSnapshot.Rest(
                        endsAt: endsAt,
                        totalSeconds: rest.totalSeconds,
                        sourceExerciseID: rest.sourceEntryID,
                        targetExerciseID: rest.targetEntryID,
                        targetSetID: rest.targetSetID
                    )
                }
            }
        )
    }

    /// The Training complication's between-workouts glance, on the same
    /// week boundary the iPhone training widget uses.
    static func training(from workouts: [WorkoutSession], now: Date = Date()) -> WatchTrainingSnapshot {
        let training = WidgetSnapshotBuilder.training(from: workouts, now: now)
        return WatchTrainingSnapshot(
            workoutsThisWeek: training.workoutsThisWeek,
            lastWorkout: training.lastWorkout
        )
    }

    private static func exercise(_ entry: WorkoutExerciseEntry, defaultRestSeconds: Int) -> WatchWorkoutSnapshot.Exercise {
        WatchWorkoutSnapshot.Exercise(
            id: entry.id,
            name: ExerciseLibrary.shared.displayName(for: entry.exerciseID),
            restSeconds: entry.restSeconds ?? defaultRestSeconds,
            sets: entry.sets.sorted { $0.index < $1.index }.map { set in
                WatchWorkoutSnapshot.SetRow(
                    id: set.id,
                    index: set.index,
                    weightKg: set.weightKg,
                    reps: set.reps,
                    completed: set.completed,
                    isWarmup: set.isWarmup,
                    logsReps: set.supportsRepLogging
                )
            }
        )
    }
}
