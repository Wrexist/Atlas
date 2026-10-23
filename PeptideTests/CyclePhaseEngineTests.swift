import XCTest
@testable import Peptide

/// Pins the pure cycle-phase math (audit Phase 9 — untested engines).
/// All dates are built with `Calendar.current` day arithmetic from a
/// start-of-day anchor so the assertions hold across timezones and
/// DST transitions on CI.
@MainActor
final class CyclePhaseEngineTests: XCTestCase {

    private let calendar = Calendar.current
    /// Start-of-day anchor; every test date derives from it.
    private lazy var anchor = calendar.startOfDay(for: Date())

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: anchor)!
    }

    private func makeProtocol(
        startDate: Date,
        cycleLengthWeeks: Int = 2,
        washoutWeeks: Int = 1
    ) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Test",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            startDate: startDate,
            status: .active,
            notes: ""
        )
    }

    // MARK: - Days until the phase ends

    func test_daysUntilPhaseEnd_secondWashoutDay_countsToNextCycle() {
        // 2 weeks on, 1 week off: day 15 is wash-out day 2, and the next
        // cycle opens on day 21.
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(15))
        XCTAssertEqual(status.phase, .washout(day: 2, totalDays: 7))
        XCTAssertEqual(CyclePhaseEngine.daysUntilPhaseEnd(status, from: day(15), calendar: calendar), 6)
    }

    func test_daysUntilPhaseEnd_lastWashoutDay_isOne() {
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(20))
        XCTAssertEqual(CyclePhaseEngine.daysUntilPhaseEnd(status, from: day(20), calendar: calendar), 1)
    }

    // MARK: - On-cycle phase (2 weeks on / 1 week wash-out)

    func test_status_startDay_isOnCycleDayOne() {
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: anchor)
        XCTAssertEqual(status.phase, .onCycle(day: 1, totalDays: 14))
        XCTAssertEqual(status.phaseProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(status.cycleNumber, 1)
        XCTAssertEqual(status.phaseEndDate, day(14))
    }

    func test_status_lastOnDay_isOnCycleDayFourteen() {
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(13))
        XCTAssertEqual(status.phase, .onCycle(day: 14, totalDays: 14))
        XCTAssertEqual(status.phaseProgress, 13.0 / 14.0, accuracy: 0.0001)
        XCTAssertEqual(status.cycleNumber, 1)
    }

    // MARK: - Wash-out phase

    func test_status_dayAfterOnCycle_entersWashoutDayOne() {
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(14))
        XCTAssertEqual(status.phase, .washout(day: 1, totalDays: 7))
        XCTAssertEqual(status.phaseProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(status.cycleNumber, 1)
        XCTAssertEqual(status.phaseEndDate, day(21))
    }

    func test_status_lastWashoutDay_staysCycleOne() {
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(20))
        XCTAssertEqual(status.phase, .washout(day: 7, totalDays: 7))
        XCTAssertEqual(status.cycleNumber, 1)
    }

    // MARK: - Cycle rollover

    func test_status_dayAfterWashout_rollsIntoCycleTwo() {
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(21))
        XCTAssertEqual(status.phase, .onCycle(day: 1, totalDays: 14))
        XCTAssertEqual(status.cycleNumber, 2)
        XCTAssertEqual(status.phaseEndDate, day(35))
    }

    func test_status_midThirdCycle_reportsCycleThree() {
        // Day 45 = two full 21-day periods (42) + 3 → cycle 3, on-day 4.
        let status = CyclePhaseEngine.status(for: makeProtocol(startDate: anchor), at: day(45))
        XCTAssertEqual(status.phase, .onCycle(day: 4, totalDays: 14))
        XCTAssertEqual(status.cycleNumber, 3)
    }

    // MARK: - No wash-out: single run then completed

    func test_status_noWashout_completesAfterOnCycle() {
        let proto = makeProtocol(startDate: anchor, washoutWeeks: 0)
        let status = CyclePhaseEngine.status(for: proto, at: day(14))
        XCTAssertEqual(status.phase, .completed)
        XCTAssertEqual(status.phaseProgress, 1.0, accuracy: 0.0001)
        XCTAssertEqual(status.cycleNumber, 1)
        XCTAssertEqual(status.phaseEndDate, day(14))
    }

    func test_status_noWashout_staysCompletedLongAfter() {
        let proto = makeProtocol(startDate: anchor, washoutWeeks: 0)
        XCTAssertEqual(CyclePhaseEngine.status(for: proto, at: day(100)).phase, .completed)
    }

    func test_status_noWashout_lastDayStillOnCycle() {
        let proto = makeProtocol(startDate: anchor, washoutWeeks: 0)
        let status = CyclePhaseEngine.status(for: proto, at: day(13))
        XCTAssertEqual(status.phase, .onCycle(day: 14, totalDays: 14))
    }

    // MARK: - Upcoming

    func test_status_beforeStart_isUpcomingWithDayCount() {
        let proto = makeProtocol(startDate: day(5))
        let status = CyclePhaseEngine.status(for: proto, at: anchor)
        XCTAssertEqual(status.phase, .upcoming(daysUntilStart: 5))
        XCTAssertEqual(status.phaseProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(status.cycleNumber, 1)
        XCTAssertEqual(status.phaseEndDate, day(5))
    }

    func test_status_dayBeforeStart_isUpcomingOneDay() {
        let proto = makeProtocol(startDate: day(1))
        XCTAssertEqual(
            CyclePhaseEngine.status(for: proto, at: anchor).phase,
            .upcoming(daysUntilStart: 1)
        )
    }

    // MARK: - isOnCycle (2 weeks on / 1 week wash-out)

    func test_isOnCycle_washoutWeek_isOff() {
        let proto = makeProtocol(startDate: anchor)
        XCTAssertTrue(CyclePhaseEngine.isOnCycle(day(13), protocol: proto, calendar: calendar))
        XCTAssertFalse(CyclePhaseEngine.isOnCycle(day(14), protocol: proto, calendar: calendar))
        XCTAssertFalse(CyclePhaseEngine.isOnCycle(day(20), protocol: proto, calendar: calendar))
    }

    func test_isOnCycle_secondCycle_isOnAgain() {
        let proto = makeProtocol(startDate: anchor)
        XCTAssertTrue(CyclePhaseEngine.isOnCycle(day(21), protocol: proto, calendar: calendar))
        XCTAssertTrue(CyclePhaseEngine.isOnCycle(day(34), protocol: proto, calendar: calendar))
    }

    func test_isOnCycle_noWashout_endsAfterFirstCycle() {
        let proto = makeProtocol(startDate: anchor, washoutWeeks: 0)
        XCTAssertTrue(CyclePhaseEngine.isOnCycle(day(13), protocol: proto, calendar: calendar))
        XCTAssertFalse(CyclePhaseEngine.isOnCycle(day(21), protocol: proto, calendar: calendar))
    }

    func test_isOnCycle_beforeStart_isOff() {
        let proto = makeProtocol(startDate: anchor)
        XCTAssertFalse(CyclePhaseEngine.isOnCycle(day(-1), protocol: proto, calendar: calendar))
    }

    // MARK: - Glyphs (pure switch; copy/colors are render concerns)

    func test_icon_isStablePerPhase() {
        XCTAssertEqual(CyclePhaseEngine.icon(for: .onCycle(day: 1, totalDays: 14)), "syringe.fill")
        XCTAssertEqual(CyclePhaseEngine.icon(for: .washout(day: 1, totalDays: 7)), "moon.stars.fill")
        XCTAssertEqual(CyclePhaseEngine.icon(for: .completed), "checkmark.seal.fill")
        XCTAssertEqual(CyclePhaseEngine.icon(for: .upcoming(daysUntilStart: 3)), "calendar")
    }
}
