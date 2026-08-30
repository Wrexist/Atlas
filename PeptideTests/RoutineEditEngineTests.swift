import XCTest
@testable import Peptide

/// The structural edits behind the routine list and builder. Re-indexing
/// is the whole game here: `RoutineExercise.index` is what the session
/// seeder reads, so a drag that leaves it stale reorders the card and not
/// the workout.
final class RoutineEditEngineTests: XCTestCase {

    private func routine(_ name: String, sortIndex: Int? = nil, exerciseIDs: [String] = []) -> Routine {
        Routine(
            name: name,
            exercises: exerciseIDs.enumerated().map {
                RoutineExercise(exerciseID: $1, index: $0)
            },
            sortIndex: sortIndex
        )
    }

    // MARK: - List ordering

    func test_reindexed_numbersFromZeroInArrayOrder() {
        let list = [routine("A", sortIndex: 7), routine("B"), routine("C", sortIndex: 2)]

        XCTAssertEqual(RoutineEditEngine.reindexed(list).map(\.sortIndex), [0, 1, 2])
    }

    func test_moved_placesRoutineAtDestination_andRenumbers() {
        let list = RoutineEditEngine.reindexed([routine("A"), routine("B"), routine("C")])

        let result = RoutineEditEngine.moved(list, fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(result.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(result.map(\.sortIndex), [0, 1, 2])
    }

    /// A never-reordered library is all-nil; the first drag has to give
    /// every row a concrete key or the order won't survive a reload.
    func test_moved_fromUnorderedLibrary_assignsEveryRowAKey() {
        let list = [routine("A"), routine("B"), routine("C")]

        let result = RoutineEditEngine.moved(list, fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(result.map(\.name), ["B", "C", "A"])
        XCTAssertFalse(result.contains { $0.sortIndex == nil })
    }

    // MARK: - Duplicate

    func test_duplicate_takesAFreshIdentity() {
        let original = routine("Push day", exerciseIDs: ["Barbell_Squat", "Barbell_Curl"])

        let copy = RoutineEditEngine.duplicate(original, existingNames: ["Push day"])

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.exercises.map(\.exerciseID), original.exercises.map(\.exerciseID))
        XCTAssertTrue(Set(copy.exercises.map(\.id)).isDisjoint(with: Set(original.exercises.map(\.id))),
                      "Shared slot ids would make the two routines edit each other")
    }

    func test_duplicate_namesTheCopyFinderStyle() {
        let original = routine("Push day")

        XCTAssertEqual(
            RoutineEditEngine.duplicate(original, existingNames: ["Push day"]).name,
            "Push day copy"
        )
    }

    func test_duplicate_ofACopy_numbersTheNextOne() {
        let original = routine("Push day")
        let taken = ["Push day", "Push day copy"]

        XCTAssertEqual(
            RoutineEditEngine.duplicate(original, existingNames: taken).name,
            "Push day copy 2"
        )
    }

    func test_duplicate_preservesTargetSchemeAndRest() {
        let original = Routine(
            name: "5×5",
            exercises: [
                RoutineExercise(exerciseID: "Barbell_Squat", index: 0,
                                targetSets: 5, targetReps: 5, restSeconds: 180, note: "belt on"),
            ],
            defaultRestSeconds: 120
        )

        let copy = RoutineEditEngine.duplicate(original, existingNames: [])

        XCTAssertEqual(copy.defaultRestSeconds, 120)
        XCTAssertEqual(copy.exercises[0].targetSets, 5)
        XCTAssertEqual(copy.exercises[0].targetReps, 5)
        XCTAssertEqual(copy.exercises[0].restSeconds, 180)
        XCTAssertEqual(copy.exercises[0].note, "belt on")
    }

    // MARK: - Names

    func test_sanitizedName_trimsWhitespace() {
        XCTAssertEqual(RoutineEditEngine.sanitizedName("  Leg day \n"), "Leg day")
    }

    func test_sanitizedName_blankInput_isNil() {
        XCTAssertNil(RoutineEditEngine.sanitizedName("   "))
    }

    func test_sanitizedName_capsLength() {
        let long = String(repeating: "x", count: 400)

        XCTAssertEqual(RoutineEditEngine.sanitizedName(long)?.count, RoutineEditEngine.nameLimit)
    }

    // MARK: - Slots

    func test_appending_addsSlotAtTheEnd() {
        let base = routine("Pull", exerciseIDs: ["Face_Pull"])

        let updated = RoutineEditEngine.appending(exerciseID: "Barbell_Curl", to: base)

        XCTAssertEqual(updated.exercises.map(\.exerciseID), ["Face_Pull", "Barbell_Curl"])
        XCTAssertEqual(updated.exercises.map(\.index), [0, 1])
    }

    func test_appending_theSameExerciseTwice_keepsBothSlots() {
        let base = routine("Pull", exerciseIDs: ["Face_Pull"])

        let updated = RoutineEditEngine.appending(exerciseID: "Face_Pull", to: base)

        XCTAssertEqual(updated.exercises.count, 2,
                       "Two slots on one lift is a legitimate routine, not a duplicate")
        XCTAssertNotEqual(updated.exercises[0].id, updated.exercises[1].id)
    }

    func test_removingSlot_closesTheIndexGap() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat", "Leg_Press", "Lying_Leg_Curls"])

        let updated = RoutineEditEngine.removingSlot(id: base.exercises[1].id, from: base)

        XCTAssertEqual(updated.exercises.map(\.exerciseID), ["Barbell_Squat", "Lying_Leg_Curls"])
        XCTAssertEqual(updated.exercises.map(\.index), [0, 1])
    }

    func test_removingSlot_unknownID_isANoOp() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat"])

        XCTAssertEqual(RoutineEditEngine.removingSlot(id: UUID(), from: base).exercises.count, 1)
    }

    func test_movingSlots_reordersAndRenumbers() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat", "Leg_Press", "Lying_Leg_Curls"])

        let updated = RoutineEditEngine.movingSlots(
            in: base, fromOffsets: IndexSet(integer: 0), toOffset: 3
        )

        XCTAssertEqual(updated.exercises.map(\.exerciseID),
                       ["Leg_Press", "Lying_Leg_Curls", "Barbell_Squat"])
        XCTAssertEqual(updated.exercises.map(\.index), [0, 1, 2],
                       "Index is what the seeder reads — a stale one reorders the card, not the workout")
    }

    /// Regression: normalizing after a move re-sorts by the *pre-move*
    /// index and silently undoes the drag.
    func test_movingSlots_survivesRoundTripThroughTheSeeder() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat", "Leg_Press"])

        let updated = RoutineEditEngine.movingSlots(
            in: base, fromOffsets: IndexSet(integer: 1), toOffset: 0
        )

        XCTAssertEqual(
            RoutineSeedEngine.sessionExercises(for: updated).map(\.exerciseID),
            ["Leg_Press", "Barbell_Squat"]
        )
    }

    func test_updatingTargets_writesTheNewScheme() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat"])

        let updated = RoutineEditEngine.updatingTargets(
            slotID: base.exercises[0].id, sets: 5, reps: 5, in: base
        )

        XCTAssertEqual(updated.exercises[0].targetSets, 5)
        XCTAssertEqual(updated.exercises[0].targetReps, 5)
    }

    func test_updatingTargets_clampsToWhatTheEditorCanRender() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat"])

        let updated = RoutineEditEngine.updatingTargets(
            slotID: base.exercises[0].id, sets: 0, reps: 9_999, in: base
        )

        XCTAssertEqual(updated.exercises[0].targetSets, RoutineEditEngine.targetSets.lowerBound)
        XCTAssertEqual(updated.exercises[0].targetReps, RoutineEditEngine.targetReps.upperBound)
    }

    func test_updatingTargets_unknownSlot_isANoOp() {
        let base = routine("Legs", exerciseIDs: ["Barbell_Squat"])

        let updated = RoutineEditEngine.updatingTargets(slotID: UUID(), sets: 9, reps: 9, in: base)

        XCTAssertEqual(updated.exercises[0].targetSets, base.exercises[0].targetSets)
    }

    // MARK: - Normalization

    func test_normalized_repairsDuplicateAndGappedIndices() {
        let broken = Routine(name: "Imported", exercises: [
            RoutineExercise(exerciseID: "A", index: 4),
            RoutineExercise(exerciseID: "B", index: 4),
            RoutineExercise(exerciseID: "C", index: 0),
        ])

        let fixed = RoutineEditEngine.normalized(broken)

        XCTAssertEqual(fixed.exercises.first?.exerciseID, "C")
        XCTAssertEqual(fixed.exercises.map(\.index), [0, 1, 2])
    }
}
