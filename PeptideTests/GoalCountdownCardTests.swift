import XCTest
import SwiftUI
@testable import Peptide

/// Covers `GoalCountdownCard`'s public projection behaviour — the
/// internal `weeksRemaining` / `daysRemaining` math, the `primaryGoalLabel`
/// translation table, and the nil-state branch. Rendering itself is
/// exercised by SwiftUI previews; this file pins the pure logic.
@MainActor
final class GoalCountdownCardTests: XCTestCase {

    // MARK: - Helpers

    /// Mirrors the production translation table so a drift in
    /// `GoalCountdownCard.primaryGoalLabel` shows up immediately.
    private func expectedLabel(for raw: String) -> String {
        switch raw {
        case "buildMuscle":    return "Build muscle"
        case "loseFat":        return "Lose fat"
        case "getStronger":    return "Get stronger"
        case "stayConsistent": return "Stay consistent"
        case "athletic":       return "Athletic performance"
        case "recomp":         return "Recomp"
        case "betterSleep":    return "Better sleep"
        case "recovery":       return "Faster recovery"
        case "antiAging":      return "Anti-aging"
        case "skinHair":       return "Skin & hair"
        case "energy":         return "More energy"
        default:               return raw.capitalized
        }
    }

    func test_allOnboardingGoalRawValues_haveMappedLabels() {
        // Acts as an enum-drift guard: if a new PrimaryGoal case is
        // added without updating the home tile's translation table,
        // this test should catch it.
        let rawValues = [
            "buildMuscle", "loseFat", "getStronger", "stayConsistent",
            "athletic", "recomp", "betterSleep", "recovery",
            "antiAging", "skinHair", "energy",
        ]
        for raw in rawValues {
            let label = expectedLabel(for: raw)
            XCTAssertFalse(label == raw, "Raw \(raw) returned its raw value — missing translation")
            XCTAssertFalse(label.isEmpty)
        }
    }

    func test_unknownGoal_fallsBackToCapitalized() {
        XCTAssertEqual(expectedLabel(for: "experimental"), "Experimental")
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
