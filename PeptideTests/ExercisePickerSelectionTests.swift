import XCTest
@testable import Peptide

final class ExercisePickerSelectionTests: XCTestCase {
    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, force: nil, level: .beginner, mechanic: nil,
                 equipment: nil, primaryMuscles: [], secondaryMuscles: [],
                 instructions: [], category: .strength, images: [])
    }

    func testSelectionPreservesTapOrderAndRemovesByStableID() {
        var picks = ExercisePickerSelection()
        picks.toggle(exercise("B"))
        picks.toggle(exercise("A"))
        picks.toggle(exercise("C"))
        picks.remove(id: "A")
        XCTAssertEqual(picks.exercises.map(\.id), ["B", "C"])
        picks.toggle(exercise("B"))
        picks.toggle(exercise("A"))
        XCTAssertEqual(picks.exercises.map(\.id), ["C", "A"])
    }

    func testCommitIsIdempotentAndAppendsCustomWithoutDuplicates() {
        var picks = ExercisePickerSelection()
        picks.toggle(exercise("A"))
        XCTAssertEqual(picks.takeForCommit(adding: exercise("B")).map(\.id), ["A", "B"])
        XCTAssertTrue(picks.takeForCommit().isEmpty)
        XCTAssertTrue(picks.takeForCommit(adding: exercise("C")).isEmpty)
        picks.toggle(exercise("C"))
        XCTAssertEqual(picks.exercises.map(\.id), ["A"])
        var duplicate = ExercisePickerSelection()
        duplicate.toggle(exercise("A"))
        XCTAssertEqual(duplicate.takeForCommit(adding: exercise("A")).map(\.id), ["A"])
    }

    func testClearingOrEmptyCommitDoesNotLockFutureSelection() {
        var picks = ExercisePickerSelection()
        picks.toggle(exercise("A"))
        picks.clear()
        XCTAssertTrue(picks.takeForCommit().isEmpty)
        XCTAssertFalse(picks.committed)
        picks.toggle(exercise("B"))
        XCTAssertEqual(picks.takeForCommit().map(\.id), ["B"])
    }
}
