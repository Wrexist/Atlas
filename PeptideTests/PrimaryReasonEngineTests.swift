import XCTest
@testable import Peptide

final class PrimaryReasonEngineTests: XCTestCase {

    private func coachingContext(
        hasProtocols: Bool = true,
        healthConnected: Bool = true,
        recoveryScore: Int? = nil,
        sleepHours: Double? = nil,
        adherenceRatio: Double = 0.5,
        pendingDoseCount: Int = 0,
        hourOfDay: Int = 12,
        memberDays: Int? = 100
    ) -> CoachingMessageEngine.Context {
        .init(
            hasProtocols: hasProtocols,
            healthConnected: healthConnected,
            recoveryScore: recoveryScore,
            sleepHours: sleepHours,
            adherenceRatio: adherenceRatio,
            pendingDoseCount: pendingDoseCount,
            hourOfDay: hourOfDay,
            memberDays: memberDays
        )
    }

    // MARK: - No meaningful action → graceful default, not nothing

    func test_pick_nothingSpecial_returnsOnTrackDefault() {
        let context = PrimaryReasonEngine.Context(coaching: coachingContext())
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .optionalReminder)
        XCTAssertEqual(reason.message.eyebrow, "ON TRACK")
    }

    func test_pick_onTrackDefault_enrichedWithDailyPlanHeadline() {
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(),
            dailyPlanHeadline: "Start with BPC-157 — fasted, on waking"
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .optionalReminder)
        XCTAssertEqual(reason.message.body, "Start with BPC-157 — fasted, on waking")
    }

    // MARK: - Multiple candidates → exactly one clear primary, by priority

    func test_pick_weakRecoveryBeatsHabitsDue() {
        // Both a critical recovery signal AND habits due are true —
        // critical must win.
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(recoveryScore: 30),
            habitsDueCount: 3,
            habitsDoneCount: 0
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .critical)
        XCTAssertEqual(reason.message.tone, .cautionary)
    }

    func test_pick_shortSleepIsCritical() {
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(sleepHours: 4.5),
            habitsDueCount: 2,
            habitsDoneCount: 0
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .critical)
    }

    func test_pick_habitsDueNoneCompleted_beatsTimeSensitiveCatchUp() {
        // Late in the day with pending doses (time-sensitive) AND habits
        // due with none done (high-value action) — high-value action
        // outranks time-sensitive per the retention brief's cascade.
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(pendingDoseCount: 2, hourOfDay: 20),
            habitsDueCount: 3,
            habitsDoneCount: 0
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .highValueAction)
        XCTAssertEqual(reason.message.eyebrow, "HABITS")
        XCTAssertTrue(reason.message.title.contains("3"))
    }

    func test_pick_habitsPartiallyDone_doesNotClaimHighValueAction() {
        // At least one habit already done today — this isn't the
        // "nothing started yet" moment, so it shouldn't outrank a
        // catch-up nudge.
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(pendingDoseCount: 2, hourOfDay: 20),
            habitsDueCount: 3,
            habitsDoneCount: 1
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .timeSensitive)
    }

    func test_pick_lateDayCatchUp_beatsProgressInsight() {
        // Neutral recovery score (neither strong nor weak) so the
        // time-sensitive catch-up branch is actually reachable — a strong
        // score would resolve via the earlier progress-insight (recovery)
        // branch instead, per CoachingMessageEngine's own cascade order.
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(recoveryScore: 55, pendingDoseCount: 1, hourOfDay: 20),
            weeklyReviewHeadline: "Compliance up 12% from last week"
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .timeSensitive)
    }

    func test_pick_strongRecoveryLateDayWithPendingDoses_isNotMislabeledTimeSensitive() {
        // Strong recovery AND late-day-with-pending-doses are both true,
        // but CoachingMessageEngine's own cascade checks strong recovery
        // first (see CoachingMessageEngine.pick), so `coaching` here is
        // the strong-recovery message, not a catch-up one. Tagging it
        // "time-sensitive" would mislabel it — it must resolve as the
        // recovery half of progress-insight instead.
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(recoveryScore: 90, pendingDoseCount: 3, hourOfDay: 20)
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .progressInsight)
        XCTAssertEqual(reason.message.eyebrow, "COACHING")
        XCTAssertTrue(reason.message.title.contains("90"))
    }

    func test_pick_weeklyReviewHeadline_winsProgressInsightOverStrongRecovery() {
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(recoveryScore: 85),
            weeklyReviewHeadline: "Compliance up 12% from last week"
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .progressInsight)
        XCTAssertEqual(reason.message.eyebrow, "WEEKLY REVIEW")
        XCTAssertEqual(reason.message.body, "Compliance up 12% from last week")
    }

    func test_pick_strongRecoveryWithNoWeeklyReview_isProgressInsight() {
        let context = PrimaryReasonEngine.Context(coaching: coachingContext(recoveryScore: 90))
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .progressInsight)
        XCTAssertEqual(reason.message.eyebrow, "COACHING")
    }

    func test_pick_welcomeMessage_isOptionalReminder() {
        let context = PrimaryReasonEngine.Context(
            coaching: coachingContext(hasProtocols: false, memberDays: 2)
        )
        let reason = PrimaryReasonEngine.pick(context: context)
        XCTAssertEqual(reason.priority, .optionalReminder)
        XCTAssertEqual(reason.message.eyebrow, "WELCOME")
    }
}
