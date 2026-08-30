import XCTest
@testable import Peptide

/// Covers `notificationBody(for:)` / `mostRecentSummaries(in:)` — the pure
/// pieces of the scheduler that decide what copy a Sunday push carries.
/// `schedule`/`cancel`/`reconcile` themselves talk to
/// `UNUserNotificationCenter` and aren't covered here, matching how the rest
/// of the notification layer is tested (see `NotificationServiceTests`).
@MainActor
final class WeeklySummaryNotificationSchedulerTests: XCTestCase {

    private func makeSummary(
        weekStart: String,
        compliancePct: Double = 0.7,
        currentStreak: Int = 3,
        hrvDelta: Int? = nil
    ) -> WeeklySummary {
        WeeklySummary(
            weekStart: weekStart,
            text: "",
            keyStats: WeeklySummary.KeyStats(
                compliancePct: compliancePct,
                dosesCompleted: 7,
                dosesTotal: 10,
                currentStreak: currentStreak,
                avgCheckInScore: nil,
                avgCalories: nil,
                hrvDelta: hrvDelta
            ),
            kind: .offline,
            generatedAt: Date()
        )
    }

    func test_notificationBody_noSummaries_returnsGenericBody() {
        let profile = UserProfile.fresh
        XCTAssertEqual(
            WeeklySummaryNotificationScheduler.notificationBody(for: profile),
            WeeklySummaryNotificationScheduler.genericBody
        )
    }

    func test_notificationBody_onlyOneSummaryEverGenerated_returnsGenericBody() {
        // A single stored summary has nothing to diff against —
        // mostRecentSummaries returns (current, nil), and changeHeadline
        // requires a previous summary.
        var profile = UserProfile.fresh
        let only = makeSummary(weekStart: "2026-01-05", compliancePct: 0.95)
        profile.weeklySummaries = [only.weekStart: only]
        XCTAssertEqual(
            WeeklySummaryNotificationScheduler.notificationBody(for: profile),
            WeeklySummaryNotificationScheduler.genericBody
        )
    }

    func test_notificationBody_noMeaningfulDelta_returnsGenericBody() {
        var profile = UserProfile.fresh
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.71, currentStreak: 3)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.70, currentStreak: 3)
        profile.weeklySummaries = [current.weekStart: current, previous.weekStart: previous]
        XCTAssertEqual(
            WeeklySummaryNotificationScheduler.notificationBody(for: profile),
            WeeklySummaryNotificationScheduler.genericBody
        )
    }

    func test_notificationBody_realDelta_usesChangeHeadlineWithRecapSuffix() {
        var profile = UserProfile.fresh
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.9)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7)
        profile.weeklySummaries = [current.weekStart: current, previous.weekStart: previous]
        XCTAssertEqual(
            WeeklySummaryNotificationScheduler.notificationBody(for: profile),
            "Compliance up 20% from last week — tap for the full recap."
        )
    }

    func test_notificationBody_picksTwoMostRecentByWeekStart_ignoresOlderHistory() {
        // Three summaries on file — an old one shouldn't be picked as
        // "previous" over the one immediately preceding "current".
        var profile = UserProfile.fresh
        let old = makeSummary(weekStart: "2025-12-01", compliancePct: 0.3)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7)
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.9)
        profile.weeklySummaries = [
            old.weekStart: old,
            previous.weekStart: previous,
            current.weekStart: current,
        ]
        // Were `old` (30% compliance) picked as "previous" instead of the
        // real prior week (70%), the delta would still clear the
        // meaningful-change floor but report a different, wrong number.
        XCTAssertEqual(
            WeeklySummaryNotificationScheduler.notificationBody(for: profile),
            "Compliance up 20% from last week — tap for the full recap."
        )
    }
}
