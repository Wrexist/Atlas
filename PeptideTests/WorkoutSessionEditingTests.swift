import XCTest
@testable import Peptide

final class WorkoutSessionEditingTests: XCTestCase {

    private let finished = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ exercises: [WorkoutExerciseEntry]) -> WorkoutSession {
        WorkoutSession(
            name: "Push",
            startedAt: finished.addingTimeInterval(-3_600),
            finishedAt: finished,
            exercises: exercises
        )
    }

    private func entry(_ id: String, index: Int, sets: [(Double, Int)]) -> WorkoutExerciseEntry {
        WorkoutExerciseEntry(exerciseID: id, index: index, sets: sets.enumerated().map { i, set in
            SetEntry(index: i + 1, weightKg: set.0, reps: set.1, completed: true, completedAt: finished)
        })
    }

    func test_addedExercise_isOneCompletedSetSeededFromHistory() throws {
        var workout = session([entry("bench", index: 0, sets: [(80, 8)])])
        let seed = SetEntry(index: 3, weightKg: 22.5, reps: 12, completed: true)

        workout.appendLoggedExercise("fly", seed: seed)

        let added = try XCTUnwrap(workout.exercises.last)
        XCTAssertEqual(added.exerciseID, "fly")
        XCTAssertEqual(added.index, 1)
        XCTAssertEqual(added.sets.count, 1)
        XCTAssertEqual(added.sets[0].weightKg, 22.5)
        XCTAssertEqual(added.sets[0].reps, 12)
        XCTAssertTrue(added.sets[0].completed)
        XCTAssertEqual(added.sets[0].completedAt, finished)
        XCTAssertEqual(workout.completedSetCount, 2)
    }

    func test_addedExerciseWithoutHistory_startsAtEightEmptyReps() throws {
        var workout = session([])
        workout.appendLoggedExercise("fly", seed: nil)

        let set = try XCTUnwrap(workout.exercises.first?.sets.first)
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertEqual(set.reps, 8)
    }

    func test_addedSet_copiesTheLastWorkingSetAndCountsTowardVolume() throws {
        var workout = session([entry("bench", index: 0, sets: [(80, 8), (85, 6)])])
        let volumeBefore = workout.totalVolumeKg
        let id = try XCTUnwrap(workout.exercises.first?.id)

        workout.appendLoggedSet(toEntry: id)

        let sets = try XCTUnwrap(workout.exercises.first?.sets)
        XCTAssertEqual(sets.map(\.index), [1, 2, 3])
        XCTAssertEqual(sets[2].weightKg, 85)
        XCTAssertEqual(sets[2].reps, 6)
        XCTAssertTrue(sets[2].completed)
        XCTAssertEqual(workout.totalVolumeKg, volumeBefore + 85 * 6, accuracy: 0.001)
    }

    func test_removedSet_renumbersTheRest() throws {
        var workout = session([entry("bench", index: 0, sets: [(80, 8), (85, 6), (90, 4)])])
        let id = try XCTUnwrap(workout.exercises.first?.id)

        workout.removeLoggedSets(atOffsets: IndexSet(integer: 0), fromEntry: id)

        let sets = try XCTUnwrap(workout.exercises.first?.sets)
        XCTAssertEqual(sets.map(\.index), [1, 2])
        XCTAssertEqual(sets.map(\.weightKg), [85, 90])
    }

    func test_removingAnExercisesLastSet_removesTheExercise() throws {
        var workout = session([
            entry("bench", index: 0, sets: [(80, 8)]),
            entry("row", index: 1, sets: [(60, 10)]),
        ])
        let bench = try XCTUnwrap(workout.exercises.first?.id)

        workout.removeLoggedSets(atOffsets: IndexSet(integer: 0), fromEntry: bench)

        XCTAssertEqual(workout.exercises.map(\.exerciseID), ["row"])
        XCTAssertEqual(workout.exercises.first?.index, 0)
    }

    func test_removedExercise_leavesNoLoneSuperset() throws {
        let group = UUID()
        var first = entry("bench", index: 0, sets: [(80, 8)])
        var second = entry("row", index: 1, sets: [(60, 10)])
        first.supersetGroup = group
        second.supersetGroup = group
        var workout = session([first, second, entry("curl", index: 2, sets: [(15, 12)])])

        workout.removeLoggedExercise(entryID: first.id)

        XCTAssertEqual(workout.exercises.map(\.exerciseID), ["row", "curl"])
        XCTAssertEqual(workout.exercises.map(\.index), [0, 1])
        XCTAssertNil(workout.exercises.first?.supersetGroup)
    }
}
