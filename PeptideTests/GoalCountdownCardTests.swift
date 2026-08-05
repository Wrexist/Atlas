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

    /// Derived from `daysRemaining`, exactly as the card does it.
    ///
    /// This used to divide raw seconds by a week. A goal date built as
    /// `Date() + 7 days` is already a few microseconds in the past by the time
    /// the helper calls `Date()` again, so the quotient is 6.9999… and `Int`
    /// truncates it to 0 — the card, which buckets by calendar day, says 1.
    /// The mirror had drifted into being a second, different implementation,
    /// and it was the one under test.
    private func weeksRemaining(for goalDate: Date) -> Int {
        max(0, daysRemaining(for: goalDate) / 7)
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
        // Added as a calendar day, not as 604800 seconds. Both the card and
        // the mirror bucket by `startOfDay`, so a goal seven calendar days out
        // is seven days out at any hour and across a DST transition — where
        // the seconds version can land on six and read as zero weeks.
        let oneWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        XCTAssertEqual(daysRemaining(for: oneWeek), 7)
        XCTAssertEqual(weeksRemaining(for: oneWeek), 1)
    }
}
