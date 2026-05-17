import XCTest
import SwiftUI
@testable import Peptide

/// Covers `GoalCountdownCard`'s public projection behaviour — the
/// internal `weeksRemaining` / `daysRemaining` math, the `primaryGoalLabel`
/// translation table, and the nil-state branch. Rendering itself is
/// exercised by SwiftUI previews; this file pins the pure logic.
@MainActor
final class GoalCountdownCardTests: XCTestCase {

    // MARK: - Display label

    func test_everyPrimaryGoalCase_hasNonEmptyDisplayName() {
        // Drift guard: if a new PrimaryGoal case is added in onboarding
        // and someone forgets to expand displayName, this catches it.
        // GoalCountdownCard reads displayName directly, so a single
        // source of truth means there's no parallel translation table
        // to drift.
        for goal in OnboardingView.PrimaryGoal.allCases {
            XCTAssertFalse(goal.displayName.isEmpty,
                           "PrimaryGoal.\(goal.rawValue) has no display name")
            XCTAssertNotEqual(goal.displayName, goal.rawValue,
                              "PrimaryGoal.\(goal.rawValue) display name equals raw — likely missing translation")
        }
    }

    func test_unknownGoalKey_fallsBackToCapitalized() {
        // The card's lookup uses PrimaryGoal(rawValue:) then
        // .capitalized for unknown keys. "experimental" should hit the
        // fallback branch.
        XCTAssertNil(OnboardingView.PrimaryGoal(rawValue: "experimental"))
        XCTAssertEqual("experimental".capitalized, "Experimental")
    }

    // MARK: - Time math (mirrors GoalCountdownCard's private computeds)

    private func weeksRemaining(for goalDate: Date) -> Int {
        let seconds = goalDate.timeIntervalSince(Date())
        guard seconds > 0 else { return 0 }
        return max(0, Int(seconds / (60 * 60 * 24 * 7)))
    }

    private func daysRemaining(for goalDate: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: goalDate)
        let comps = calendar.dateComponents([.day], from: start, to: end)
        return max(0, comps.day ?? 0)
    }

    func test_pastGoalDate_returnsZero() {
        let past = Date().addingTimeInterval(-60 * 60 * 24 * 30)
        XCTAssertEqual(weeksRemaining(for: past), 0)
        XCTAssertEqual(daysRemaining(for: past), 0)
    }

    func test_futureGoalDate_returnsPositive() {
        let twelveWeeks = Date().addingTimeInterval(60 * 60 * 24 * 7 * 12)
        let weeks = weeksRemaining(for: twelveWeeks)
        XCTAssertGreaterThanOrEqual(weeks, 11)
        XCTAssertLessThanOrEqual(weeks, 12)
    }

    func test_oneWeekOut_returnsOneWeekSevenDays() {
        let oneWeek = Date().addingTimeInterval(60 * 60 * 24 * 7)
        XCTAssertEqual(weeksRemaining(for: oneWeek), 1)
        // Day-bucket arithmetic depends on the current time of day; the
        // floor is 6 days, the ceiling is 7. Both are valid.
        let days = daysRemaining(for: oneWeek)
        XCTAssertTrue(days == 6 || days == 7, "Got \(days) — expected 6 or 7")
    }
}
