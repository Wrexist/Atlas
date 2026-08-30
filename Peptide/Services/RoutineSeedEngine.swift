import Foundation

/// Turns a `Routine` — the plan — into the concrete exercise/set rows a
/// `WorkoutSession` starts life with, plus the two derived numbers the
/// routine list renders (set count, estimated duration).
///
/// Pure and synchronous so the seeding contract is testable without a
/// store: `WorkoutSessionService` owns persistence, this owns the shape.
enum RoutineSeedEngine {

    /// Upper bound on seeded sets per exercise. A routine slot is user
    /// input, and a mistyped `targetSets` shouldn't hand the active
    /// workout screen thousands of rows to lay out.
    static let maxSeededSets = 20

    /// Seconds a working set takes, excluding rest. Used only for the
    /// "~48 min" estimate on the routine card — deliberately coarse.
    static let secondsPerSet = 40

    /// Rest used for the duration estimate when neither the slot nor the
    /// routine specifies one. Mirrors `TrainingPreferences.restTimerDefault`'s
    /// own default so the estimate matches the timer the user will see.
    static let fallbackRestSeconds = 90

    /// Builds the session's exercise entries from the routine's slots.
    ///
    /// `previousSet` supplies the user's last logged set for an exercise
    /// so the first row opens at the weight they actually lift instead of
    /// 0 kg. Reps still come from the routine — that target is the reason
    /// the user wrote the routine down.
    static func sessionExercises(
        for routine: Routine,
        previousSet: (String) -> SetEntry? = { _ in nil }
    ) -> [WorkoutExerciseEntry] {
        routine.exercises
            .sorted { $0.index < $1.index }
            .enumerated()
            .map { position, slot in
                WorkoutExerciseEntry(
                    exerciseID: slot.exerciseID,
                    index: position,
                    sets: seededSets(for: slot, previous: previousSet(slot.exerciseID)),
                    note: slot.note,
                    restSeconds: slot.restSeconds ?? routine.defaultRestSeconds
                )
            }
    }

    private static func seededSets(
        for slot: RoutineExercise,
        previous: SetEntry?
    ) -> [SetEntry] {
        let count = min(max(1, slot.targetSets), maxSeededSets)
        let weight = SetEntryLimits.clampWeightKg(previous?.weightKg ?? 0)
        let reps = SetEntryLimits.clampReps(slot.targetReps)
        return (1...count).map { index in
            SetEntry(index: index, weightKg: weight, reps: reps, rpe: slot.targetRPE)
        }
    }

    // MARK: - Derived figures

    /// Total target sets across the routine. The routine card's headline
    /// number, and what makes two routines comparable at a glance.
    static func totalSets(in routine: Routine) -> Int {
        routine.exercises.reduce(0) { $0 + min(max(1, $1.targetSets), maxSeededSets) }
    }

    /// Rough wall-clock minutes: work plus rest between sets. Rounded to
    /// the nearest 5 so the card reads as the estimate it is rather than
    /// promising "47 min".
    static func estimatedMinutes(for routine: Routine) -> Int {
        guard !routine.exercises.isEmpty else { return 0 }
        let seconds = routine.exercises.reduce(0) { total, slot in
            let sets = min(max(1, slot.targetSets), maxSeededSets)
            let rest = slot.restSeconds ?? routine.defaultRestSeconds ?? fallbackRestSeconds
            // One fewer rest than sets — the last set of an exercise runs
            // into the next exercise's setup, not a logged rest.
            return total + sets * secondsPerSet + max(0, sets - 1) * rest
        }
        return max(5, Int((Double(seconds) / 60.0 / 5.0).rounded()) * 5)
    }
}
