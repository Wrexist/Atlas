import XCTest
@testable import Peptide

/// The starter templates are hardcoded exercise slugs. If a dataset
/// refresh renames one, the routine still creates — it just renders a
/// blank row the user can't fix. That failure belongs in CI.
@MainActor
final class RoutineTemplateTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    func test_everyStarterSlug_resolvesInTheBundledLibrary() {
        let library = ExerciseLibrary.shared
        for template in RoutineTemplate.starters {
            for slot in template.slots {
                XCTAssertNotNil(
                    library.lookup(id: slot.exerciseID),
                    "\(template.name) references '\(slot.exerciseID)', which is not in exercises.json"
                )
            }
        }
    }

    func test_starterIDsAreUnique() {
        let ids = RoutineTemplate.starters.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_everyStarterHasExercisesAndAName() {
        for template in RoutineTemplate.starters {
            XCTAssertFalse(template.name.isEmpty)
            XCTAssertFalse(template.summary.isEmpty)
            XCTAssertGreaterThanOrEqual(template.slots.count, 3,
                                        "\(template.name) is too thin to read as a routine")
        }
    }

    func test_makeExercises_numbersSlotsInOrder() {
        let template = RoutineTemplate.starters[0]

        let exercises = template.makeExercises()

        XCTAssertEqual(exercises.map(\.index), Array(0..<template.slots.count))
        XCTAssertEqual(exercises.map(\.exerciseID), template.slots.map(\.exerciseID))
    }

    func test_makeExercises_carriesTheSetScheme() throws {
        let fiveByFive = RoutineTemplate.starters.first { $0.id == "strong-5x5" }
        let exercises = try XCTUnwrap(fiveByFive).makeExercises()

        XCTAssertTrue(exercises.allSatisfy { $0.targetSets == 5 && $0.targetReps == 5 })
    }

    /// A starter has to survive the same path a hand-built routine takes.
    func test_starter_seedsAWorkableSession() {
        let template = RoutineTemplate.starters[0]
        let routine = Routine(name: template.name, exercises: template.makeExercises())

        let entries = RoutineSeedEngine.sessionExercises(for: routine)

        XCTAssertEqual(entries.count, template.slots.count)
        XCTAssertTrue(entries.allSatisfy { !$0.sets.isEmpty })
    }
}
