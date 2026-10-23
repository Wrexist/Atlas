import XCTest
@testable import Peptide

final class LegacyGoalMigrationTests: XCTestCase {

    func test_migrate_legacyLabels_becomePrimaryGoalKeys() {
        let result = LegacyGoalMigration.migrate(
            goals: ["Better Sleep", "Fat Loss", "Anti-Aging"],
            primaryGoal: "Better Sleep"
        )
        XCTAssertEqual(result.goals, ["betterSleep", "loseFat", "antiAging"])
        XCTAssertEqual(result.primaryGoal, "betterSleep")
    }

    func test_migrate_twoLabelsForOneGoal_keepsOneKey() {
        let result = LegacyGoalMigration.migrate(goals: ["Muscle Recovery", "Joint Health"], primaryGoal: nil)
        XCTAssertEqual(result.goals, ["recovery"])
    }

    func test_migrate_retiredPinnedLabel_dropsGoalAndPin() {
        let result = LegacyGoalMigration.migrate(
            goals: ["Cognitive Edge", "buildMuscle"],
            primaryGoal: "Cognitive Edge"
        )
        XCTAssertEqual(result.goals, ["buildMuscle"])
        XCTAssertNil(result.primaryGoal)
    }

    func test_migrate_currentKeysAndUnknownStrings_areUnchanged() {
        let goals = ["buildMuscle", "Longevity"]
        let result = LegacyGoalMigration.migrate(goals: goals, primaryGoal: "buildMuscle")
        XCTAssertEqual(result.goals, goals)
        XCTAssertEqual(result.primaryGoal, "buildMuscle")
    }
}
