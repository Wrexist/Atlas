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

    /// Routines the wrist lists at once; the rest stay on the phone. Keeps
    /// the application context, which carries the whole snapshot, small.
    static let catalogRoutineLimit = 12
    /// Lifts per routine, and recent lifts, the wrist carries.
    static let catalogLiftLimit = 16

    /// What the Watch can start while the phone is out of reach: each
    /// routine seeded the way `WorkoutSessionService.startWorkout` seeds
    /// it from the user's last sets, and the lifts logged in `recent`
    /// (newest first) for a quick workout. `lastSet` is the last completed
    /// set of an exercise; `name` resolves a library id.
    static func catalog(
        routines: [Routine],
        recent: [WorkoutSession],
        defaultRestSeconds: Int,
        lastSet: (String) -> SetEntry?,
        name: (String) -> String
    ) -> WatchTrainingCatalog {
        let watchRoutines = routines.prefix(catalogRoutineLimit).map { routine in
            WatchRoutine(
                id: routine.id,
                name: routine.name,
                lifts: RoutineSeedEngine.sessionExercises(for: routine, previousSet: lastSet)
                    .prefix(catalogLiftLimit)
                    .compactMap { lift(from: $0, defaultRestSeconds: defaultRestSeconds, name: name) }
            )
        }
        var seen = Set<String>()
        let recentLifts = recent
            .filter { $0.finishedAt != nil }
            .flatMap { session in session.exercises.sorted { $0.index < $1.index } }
            .filter { seen.insert($0.exerciseID).inserted }
            .compactMap { entry -> WatchLift? in
                guard let last = lastSet(entry.exerciseID), last.supportsRepLogging else { return nil }
                return WatchLift(
                    exerciseID: entry.exerciseID,
                    name: name(entry.exerciseID),
                    restSeconds: entry.restSeconds ?? defaultRestSeconds,
                    sets: max(1, entry.completedWorkingSets.count),
                    weightKg: last.weightKg,
                    reps: last.reps,
                    measurement: last.measurement.map { WatchSetMeasurement($0) }
                )
            }
            .prefix(catalogLiftLimit)
        return WatchTrainingCatalog(routines: watchRoutines, recentLifts: Array(recentLifts))
    }

    /// A seeded routine entry as the Watch logs it. Nil for an entry the
    /// Watch can't log reps for, like a timed hold.
    private static func lift(
        from entry: WorkoutExerciseEntry,
        defaultRestSeconds: Int,
        name: (String) -> String
    ) -> WatchLift? {
        guard let first = entry.sets.first, first.supportsRepLogging else { return nil }
        return WatchLift(
            exerciseID: entry.exerciseID,
            name: name(entry.exerciseID),
            restSeconds: entry.restSeconds ?? defaultRestSeconds,
            sets: entry.sets.count,
            weightKg: first.weightKg,
            reps: first.reps,
            measurement: first.measurement.map { WatchSetMeasurement($0) }
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
                    logsReps: set.supportsRepLogging,
                    measurement: set.measurement.map { WatchSetMeasurement($0) }
                )
            }
        )
    }
}

extension WatchSetMeasurement {
    init(_ measurement: SetEntry.Measurement) {
        self.init(kind: measurement.kind.rawValue, load: measurement.load.rawValue)
    }
}
