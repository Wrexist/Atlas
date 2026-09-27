import XCTest
@testable import Peptide

/// "Save as routine" and "Repeat workout" both turn a logged session back
/// into a plan. The slot targets come from the working sets the user did,
/// so warm-ups and unchecked rows must not inflate them.
final class RoutineReplayTests: XCTestCase {

    private func set(_ index: Int, reps: Int, completed: Bool = true, warmup: Bool = false) -> SetEntry {
        SetEntry(index: index, weightKg: 60, reps: reps, completed: completed, isWarmup: warmup)
    }

    private func session(_ entries: [WorkoutExerciseEntry]) -> WorkoutSession {
        WorkoutSession(name: "Push", finishedAt: Date(), exercises: entries)
    }

    func test_replaying_keepsExerciseOrderByEntryIndex() {
        let routine = Routine(replaying: session([
            WorkoutExerciseEntry(exerciseID: "Dips", index: 1, sets: [set(1, reps: 12)]),
            WorkoutExerciseEntry(exerciseID: "Bench", index: 0, sets: [set(1, reps: 5)])
        ]), name: "Push")

        XCTAssertEqual(routine.name, "Push")
        XCTAssertEqual(routine.exercises.map(\.exerciseID), ["Bench", "Dips"])
        XCTAssertEqual(routine.exercises.map(\.index), [0, 1])
    }

    func test_replaying_countsCompletedWorkingSets_andIgnoresWarmups() {
        let entry = WorkoutExerciseEntry(exerciseID: "Bench", index: 0, sets: [
            set(1, reps: 10, warmup: true),
            set(2, reps: 5),
            set(3, reps: 5),
            set(4, reps: 5, completed: false)
        ])

        let slot = Routine(replaying: session([entry]), name: "Push").exercises.first

        XCTAssertEqual(slot?.targetSets, 2)
        XCTAssertEqual(slot?.targetReps, 5)
    }

    func test_replaying_nothingCompleted_fallsBackToPlannedWorkingSets() {
        let entry = WorkoutExerciseEntry(exerciseID: "Row", index: 0, sets: [
            set(1, reps: 8, completed: false),
            set(2, reps: 8, completed: false),
            set(3, reps: 8, completed: false)
        ])

        let slot = Routine(replaying: session([entry]), name: "Pull").exercises.first

        XCTAssertEqual(slot?.targetSets, 3)
        XCTAssertEqual(slot?.targetReps, 8)
    }

    func test_replaying_noSetsOrReps_clampsToEditorMinimumsAndDefaults() {
        let entry = WorkoutExerciseEntry(exerciseID: "Plank", index: 0, sets: [set(1, reps: 0)])
        let empty = WorkoutExerciseEntry(exerciseID: "Curl", index: 1)

        let slots = Routine(replaying: session([entry, empty]), name: "Core").exercises

        XCTAssertEqual(slots.map(\.targetSets), [1, 1])
        XCTAssertEqual(slots.map(\.targetReps), [RoutineExercise.fallbackTargetReps, RoutineExercise.fallbackTargetReps])
    }

    func test_replaying_clampsRepsToEditorRange() {
        let entry = WorkoutExerciseEntry(exerciseID: "Jumps", index: 0, sets: [set(1, reps: 400)])

        let slot = Routine(replaying: session([entry]), name: "Cardio").exercises.first

        XCTAssertEqual(slot?.targetReps, RoutineEditEngine.targetReps.upperBound)
    }

    func test_replaying_carriesRestAndNote() {
        let entry = WorkoutExerciseEntry(
            exerciseID: "Squat", index: 0, sets: [set(1, reps: 5)],
            note: "belt on top set", restSeconds: 180
        )

        let slot = Routine(replaying: session([entry]), name: "Legs").exercises.first

        XCTAssertEqual(slot?.restSeconds, 180)
        XCTAssertEqual(slot?.note, "belt on top set")
    }

    func test_replaying_usesSuppliedID() {
        let id = UUID()

        XCTAssertEqual(Routine(replaying: session([]), name: "Push", id: id).id, id)
    }

    func test_replaying_seedsTheSameExercisesBackIntoASession() {
        let entry = WorkoutExerciseEntry(exerciseID: "Bench", index: 0, sets: [set(1, reps: 5), set(2, reps: 5)])

        let seeded = RoutineSeedEngine.sessionExercises(for: Routine(replaying: session([entry]), name: "Push"))

        XCTAssertEqual(seeded.map(\.exerciseID), ["Bench"])
        XCTAssertEqual(seeded.first?.sets.map(\.reps), [5, 5])
    }
}
