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
}
