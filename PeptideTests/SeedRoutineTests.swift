import XCTest
@testable import Peptide

final class SeedRoutineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SeedRoutineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_savedSeed_survivesReload_withItsTargets() {
        let routine = Routine(name: "Builder", exercises: [
            RoutineExercise(exerciseID: "Incline_Dumbbell_Press", index: 0, targetSets: 3, targetReps: 8)
        ])
        let seed = SeedRoutine(sessionID: UUID(), routine: routine)

        SeedRoutine.save(seed, to: defaults)

        let reloaded = SeedRoutine.load(from: defaults)
        XCTAssertEqual(reloaded, seed)
        XCTAssertEqual(reloaded?.routine.exercises.first?.targetReps, 8)
    }

    func test_savingNil_clearsTheSeed() {
        let seed = SeedRoutine(sessionID: UUID(), routine: Routine(name: "Builder", exercises: []))
        SeedRoutine.save(seed, to: defaults)

        SeedRoutine.save(nil, to: defaults)

        XCTAssertNil(SeedRoutine.load(from: defaults))
    }
}
