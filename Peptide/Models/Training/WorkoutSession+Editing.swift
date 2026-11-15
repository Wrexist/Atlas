import Foundation

/// Changes to a finished workout made after the fact — an exercise or a
/// set the user forgot to log, or one logged by mistake. Everything added
/// here counts as done at the time the workout finished.
extension WorkoutSession {
    /// Appends `exerciseID` with one completed working set, seeded from the
    /// last time it was done (`seed`), or 8 empty reps without history.
    mutating func appendLoggedExercise(_ exerciseID: String, seed: SetEntry?) {
        let set = SetEntry(
            index: 1,
            weightKg: seed?.weightKg ?? 0,
            reps: seed?.reps ?? 8,
            completed: true,
            completedAt: finishedAt,
            measurement: seed?.measurement
        )
        exercises.append(WorkoutExerciseEntry(exerciseID: exerciseID, index: exercises.count, sets: [set]))
    }

    /// Appends a completed copy of the entry's last working set, so the
    /// common "I did one more" needs no typing.
    mutating func appendLoggedSet(toEntry entryID: UUID) {
        guard let e = exercises.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = exercises[e]
        let template = entry.sets.last { !$0.isWarmup } ?? entry.sets.last
        exercises[e].sets.append(SetEntry(
            index: entry.sets.count + 1,
            weightKg: template?.weightKg ?? 0,
            reps: template?.reps ?? 8,
            rpe: template?.rpe,
            completed: true,
            completedAt: finishedAt,
            measurement: template?.measurement
        ))
    }

    /// Removes sets at `offsets`. Removing an exercise's last set removes
    /// the exercise, since an entry with no sets has nothing to show.
    mutating func removeLoggedSets(atOffsets offsets: IndexSet, fromEntry entryID: UUID) {
        guard let e = exercises.firstIndex(where: { $0.id == entryID }) else { return }
        exercises[e].sets = exercises[e].sets.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        guard !exercises[e].sets.isEmpty else {
            removeLoggedExercise(entryID: entryID)
            return
        }
        for i in exercises[e].sets.indices {
            exercises[e].sets[i].index = i + 1
        }
    }

    mutating func removeLoggedExercise(entryID: UUID) {
        exercises.removeAll { $0.id == entryID }
        for i in exercises.indices {
            exercises[i].index = i
        }
        dissolveLoneSupersets()
    }
}
