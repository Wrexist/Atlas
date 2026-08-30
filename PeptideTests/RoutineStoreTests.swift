import XCTest
@testable import Peptide

/// Store-level behaviour against a real in-memory SwiftData container:
/// the edits have to survive a reload, which is where an ordering key
/// that was only ever held in memory would fail.
@MainActor
final class RoutineStoreTests: XCTestCase {

    private var store: RoutineStore!
    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
        store = RoutineStore.shared
        store.load()
        // Both are process-wide singletons — clear anything a previous
        // case in this suite left behind.
        WorkoutSessionService.shared.discardWorkout()
    }

    override func tearDown() {
        repo.deleteAll()
        store.load()
        WorkoutSessionService.shared.discardWorkout()
        super.tearDown()
    }

    // MARK: - Create

    func test_create_persistsAndAppearsInTheLibrary() {
        let created = store.create(name: "Push day")

        XCTAssertEqual(store.routines.map(\.name), ["Push day"])
        XCTAssertEqual(repo.loadRoutines().first?.id, created.id)
    }

    func test_create_blankName_fallsBackToADefault() {
        store.create(name: "   ")

        XCTAssertEqual(store.routines.first?.name, RoutineStore.untitledName,
                       "A nameless row would be unreadable in the list")
    }

    func test_create_assignsAnIncreasingSortKey() {
        store.create(name: "A")
        store.create(name: "B")
        store.create(name: "C")

        XCTAssertEqual(store.routines.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(store.routines.compactMap(\.sortIndex), [0, 1, 2])
    }

    // MARK: - Rename

    func test_rename_writesThrough() {
        let created = store.create(name: "Push day")

        store.rename(id: created.id, to: "  Chest & triceps  ")
        store.load()

        XCTAssertEqual(store.routines.first?.name, "Chest & triceps")
    }

    func test_rename_toBlank_keepsTheOldName() {
        let created = store.create(name: "Push day")

        store.rename(id: created.id, to: "")

        XCTAssertEqual(store.routines.first?.name, "Push day")
    }

    // MARK: - Duplicate

    func test_duplicate_landsDirectlyBelowTheOriginal() {
        store.create(name: "A")
        let b = store.create(name: "B")
        store.create(name: "C")

        store.duplicate(id: b.id)

        XCTAssertEqual(store.routines.map(\.name), ["A", "B", "B copy", "C"])
        XCTAssertEqual(store.routines.compactMap(\.sortIndex), [0, 1, 2, 3])
    }

    func test_duplicate_survivesAReload() {
        let original = store.create(name: "Push day", exercises: [
            RoutineExercise(exerciseID: "Barbell_Squat", index: 0, targetSets: 5, targetReps: 5),
        ])

        store.duplicate(id: original.id)
        store.load()

        XCTAssertEqual(store.routines.map(\.name), ["Push day", "Push day copy"])
        XCTAssertEqual(store.routines.last?.exercises.first?.targetSets, 5)
    }

    func test_duplicate_unknownID_returnsNil() {
        XCTAssertNil(store.duplicate(id: UUID()))
    }

    // MARK: - Delete

    func test_delete_removesTheRowAndClosesTheOrderGap() {
        store.create(name: "A")
        let b = store.create(name: "B")
        store.create(name: "C")

        store.delete(id: b.id)
        store.load()

        XCTAssertEqual(store.routines.map(\.name), ["A", "C"])
        XCTAssertEqual(store.routines.compactMap(\.sortIndex), [0, 1])
    }

    // MARK: - Reorder

    func test_move_orderSurvivesAReload() {
        store.create(name: "A")
        store.create(name: "B")
        store.create(name: "C")

        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.load()

        XCTAssertEqual(store.routines.map(\.name), ["C", "A", "B"],
                       "A reorder held only in memory is a reorder the user loses")
    }

    /// Editing a routine after a reorder must not float it to the top —
    /// which is exactly what sorting on updatedAt alone would do.
    func test_move_thenEdit_keepsTheUserOrder() {
        store.create(name: "A")
        store.create(name: "B")
        let c = store.create(name: "C")
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        store.rename(id: c.id, to: "C renamed")
        store.load()

        XCTAssertEqual(store.routines.map(\.name), ["C renamed", "A", "B"])
    }

    // MARK: - Starting a workout

    func test_startWorkout_seedsTheSessionFromTheRoutine() {
        let routine = store.create(name: "Push day", exercises: [
            RoutineExercise(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", index: 0,
                            targetSets: 5, targetReps: 5),
            RoutineExercise(exerciseID: "Standing_Military_Press", index: 1,
                            targetSets: 3, targetReps: 8),
        ])

        let session = store.startWorkout(from: routine)

        XCTAssertEqual(session.name, "Push day")
        XCTAssertEqual(session.routineID, routine.id)
        XCTAssertEqual(session.exercises.map(\.sets.count), [5, 3])
        XCTAssertNotNil(WorkoutSessionService.shared.activeSession)
    }
}
