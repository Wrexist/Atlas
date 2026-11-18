import XCTest
@testable import Peptide

/// Pins which milestone the meal-streak badge counts down to.
@MainActor
final class MealStreakBadgeTests: XCTestCase {

    func test_streakBelowFirstMilestone_countsDownToThreeDays() {
        XCTAssertEqual(MealStreakBadge.nextMilestone(after: 1), 3)
    }

    func test_streakOnMilestone_countsDownToTheNextOne() {
        XCTAssertEqual(MealStreakBadge.nextMilestone(after: 7), 14)
    }

    func test_streakPastLastMilestone_hasNoNextMilestone() {
        XCTAssertNil(MealStreakBadge.nextMilestone(after: 365))
    }

    func test_firstStreakDay_voiceOverOmitsBestClause() {
        let label = MealStreakBadge(currentStreak: 1, bestStreak: 1).voiceOverLabel
        XCTAssertFalse(label.contains("Best"))
        XCTAssertFalse(label.contains("days"))
    }

    func test_streakBelowBest_voiceOverNamesTheBest() {
        let label = MealStreakBadge(currentStreak: 2, bestStreak: 5).voiceOverLabel
        XCTAssertTrue(label.contains("Best 5 days"))
    }
}
