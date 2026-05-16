import XCTest
@testable import Peptide

final class CoachingMessageEngineTests: XCTestCase {

    // MARK: - Priority cascade

    func test_pick_noProtocols_returnsWelcome() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: false,
            healthConnected: true,
            recoveryScore: 90,        // ignored
            sleepHours: 8,            // ignored
            adherenceRatio: 1.0       // ignored
        ))
        XCTAssertEqual(msg.tone, .welcome)
        XCTAssertEqual(msg.eyebrow, "WELCOME")
    }

    func test_pick_noHealthConnection_returnsConnectPrompt() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: false
        ))
        XCTAssertEqual(msg.eyebrow, "GET STARTED")
        XCTAssertEqual(msg.icon, "heart.text.square.fill")
    }

    func test_pick_strongRecovery_returnsPositiveCoaching() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 88,
            nextDoseAbbreviation: "BPC-157",
            nextDoseTimeDisplay: "8:00 PM"
        ))
        XCTAssertEqual(msg.tone, .positive)
        XCTAssertTrue(msg.title.contains("88%"))
        XCTAssertTrue(msg.body?.contains("BPC-157") ?? false)
    }

    func test_pick_weakRecovery_returnsCautionary() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 28
        ))
        XCTAssertEqual(msg.tone, .cautionary)
        XCTAssertTrue(msg.title.contains("28%"))
    }

    /// Short sleep wins over mid-range recovery — the user needs the
    /// sleep signal more than a generic "you're on track" line.
    func test_pick_midRecoveryShortSleep_prioritisesSleep() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 60,
            sleepHours: 5.2
        ))
        XCTAssertEqual(msg.icon, "bed.double.fill")
        XCTAssertTrue(msg.title.contains("5.2"))
    }

    /// After 6pm with pending doses → catch-up prompt regardless of
    /// other signals (other than priority winners above).
    func test_pick_lateInDayWithPending_returnsCatchUp() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 60,         // mid, skips earlier branches
            sleepHours: 7.5,            // fine, skips short-sleep
            pendingDoseCount: 2,
            hourOfDay: 20
        ))
        XCTAssertEqual(msg.icon, "clock.badge.exclamationmark.fill")
        XCTAssertTrue(msg.title.contains("2"))
    }

    /// Default branch — everything fine, day not late, no pending.
    func test_pick_onTrack_returnsPositiveOnTrack() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 65,
            sleepHours: 7.5,
            pendingDoseCount: 0,
            nextDoseAbbreviation: "CJC-1295",
            nextDoseTimeDisplay: "10:00 AM",
            hourOfDay: 9
        ))
        XCTAssertEqual(msg.tone, .positive)
        XCTAssertEqual(msg.eyebrow, "ON TRACK")
        XCTAssertTrue(msg.body?.contains("CJC-1295") ?? false)
    }

    // MARK: - Edge cases

    /// Sleep of zero (treated as "no data") must not trigger the
    /// short-sleep branch — that's reserved for actual short nights.
    func test_pick_zeroSleep_skipsShortSleepBranch() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 60,
            sleepHours: 0
        ))
        XCTAssertNotEqual(msg.icon, "bed.double.fill")
    }

    /// Late in day but no pending doses → on-track, not catch-up.
    func test_pick_lateInDayNoPending_returnsOnTrack() {
        let msg = CoachingMessageEngine.pick(context: .init(
            hasProtocols: true,
            healthConnected: true,
            recoveryScore: 65,
            sleepHours: 7.5,
            pendingDoseCount: 0,
            hourOfDay: 22
        ))
        XCTAssertEqual(msg.eyebrow, "ON TRACK")
    }
}
