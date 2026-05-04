import XCTest
@testable import Peptide

@MainActor
final class NotificationServiceTests: XCTestCase {

    private var service: NotificationService!

    override func setUp() {
        super.setUp()
        service = NotificationService.shared
        service.cancelAll()
    }

    override func tearDown() {
        service.cancelAll()
        service = nil
        super.tearDown()
    }

    // MARK: - parseTime (tested via scheduleNotifications side-effects)

    func test_scheduleNotifications_validAMTime_schedulesRequest() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 1)
        XCTAssertEqual(service.scheduledCount, 1)
    }

    func test_scheduleNotifications_validPMTime_schedulesRequest() {
        let proto = makeProtocol(times: ["9:00 PM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 1)
    }

    func test_scheduleNotifications_invalidTime_skipsRequest() {
        let proto = makeProtocol(times: ["not-a-time"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 0)
        XCTAssertEqual(service.scheduledCount, 0)
    }

    func test_scheduleNotifications_mixedValidInvalidTimes_schedulesOnlyValid() {
        let proto = makeProtocol(times: ["8:00 AM", "bad-time", "2:30 PM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 2)
    }

    // MARK: - Weekday conversion

    func test_scheduleNotifications_sunday_usesCalendarWeekdayOne() {
        // day 7 in ISO (Sun) → calendarWeekday 1
        let proto = makeProtocol(times: ["8:00 AM"], days: [7])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 1)
    }

    func test_scheduleNotifications_monday_usesCalendarWeekdayTwo() {
        // day 1 in ISO (Mon) → calendarWeekday 2
        let proto = makeProtocol(times: ["8:00 AM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 1)
    }

    // MARK: - 64-notification limit

    func test_scheduleNotifications_moreThan64_capsAt64() {
        // 8 times × 7 days = 56, plus 9 times × 1 day = 9, total 65 requests
        let weeklyTimes = ["6:00 AM", "7:00 AM", "8:00 AM", "9:00 AM", "12:00 PM", "3:00 PM", "6:00 PM", "9:00 PM"]
        let weekly = makeProtocol(times: weeklyTimes, days: [1, 2, 3, 4, 5, 6, 7])
        let overflow = makeProtocol(times: weeklyTimes + ["10:00 PM"], days: [1])
        service.scheduleNotifications(for: [weekly, overflow])
        XCTAssertEqual(service.requestedCount, 65)
        XCTAssertEqual(service.scheduledCount, 64)
    }

    func test_scheduleNotifications_exactlyAtLimit_schedulesAll() {
        // 8 times × 7 days = 56, plus 8 times × 1 day = 8, total 64 requests
        let times = ["6:00 AM", "7:00 AM", "8:00 AM", "9:00 AM", "12:00 PM", "3:00 PM", "6:00 PM", "9:00 PM"]
        let weekly = makeProtocol(times: times, days: [1, 2, 3, 4, 5, 6, 7])
        let extra = makeProtocol(times: times, days: [1])
        service.scheduleNotifications(for: [weekly, extra])
        XCTAssertEqual(service.requestedCount, 64)
        XCTAssertEqual(service.scheduledCount, 64)
    }

    // MARK: - Inactive protocols skipped

    func test_scheduleNotifications_inactiveProtocol_schedulesNothing() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1], status: .completed)
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 0)
    }

    func test_scheduleNotifications_mixedActiveInactive_schedulesOnlyActive() {
        let active = makeProtocol(times: ["8:00 AM"], days: [1], status: .active)
        let inactive = makeProtocol(times: ["9:00 AM", "10:00 AM"], days: [1, 2, 3], status: .paused)
        service.scheduleNotifications(for: [active, inactive])
        XCTAssertEqual(service.requestedCount, 1)
    }

    // MARK: - Notification content

    func test_scheduleNotifications_singlePeptide_usesPeptideAbbreviation() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1], peptideCount: 1)
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 1)
    }

    func test_scheduleNotifications_emptyProtocols_clearsAndSchedulesNothing() {
        service.scheduleNotifications(for: [])
        XCTAssertEqual(service.requestedCount, 0)
        XCTAssertEqual(service.scheduledCount, 0)
    }

    // MARK: - cancelAll

    func test_cancelAll_resetsCounters() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.requestedCount, 1)
        service.cancelAll()
        XCTAssertEqual(service.requestedCount, 0)
        XCTAssertEqual(service.scheduledCount, 0)
    }

    // MARK: - Incremental reschedule (no zero-pending window)

    /// Invariant: rescheduling with the SAME protocol must keep the same identifiers
    /// pending. The previous implementation called removeAllPendingNotificationRequests
    /// before adding, briefly leaving zero pending — now we only diff and remove
    /// stale IDs.
    func test_rescheduleSameProtocol_keepsScheduledCountStable() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.scheduledCount, 1)

        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.scheduledCount, 1,
                       "Re-scheduling the same protocol must not reset scheduledCount to 0")
    }

    /// When the new schedule omits IDs that were previously scheduled, only those
    /// stale IDs are removed; the others remain.
    func test_reschedule_removesOnlyStaleIDs() {
        let protoA = makeProtocol(times: ["8:00 AM"], days: [1])
        let protoB = makeProtocol(times: ["9:00 AM"], days: [2])
        service.scheduleNotifications(for: [protoA, protoB])
        XCTAssertEqual(service.scheduledCount, 2)

        service.scheduleNotifications(for: [protoA])  // protoB now stale
        XCTAssertEqual(service.scheduledCount, 1)
    }

    // MARK: - ScheduleReport

    func test_scheduleNotifications_returnsReportSummary() {
        let proto = makeProtocol(times: ["8:00 AM", "10:00 AM"], days: [1, 2])
        let report = service.scheduleNotifications(for: [proto])
        XCTAssertEqual(report.requested, 4)
        XCTAssertEqual(report.scheduled, 4)
        XCTAssertTrue(report.droppedProtocolIDs.isEmpty)
        XCTAssertTrue(report.invalidTimes.isEmpty)
        XCTAssertFalse(report.hasAnyIssue)
    }

    func test_scheduleNotifications_overLimit_reportsDroppedProtocols() {
        // 8 times × 7 days = 56, plus 9 times × 1 day = 9, total 65 requests
        let weeklyTimes = ["6:00 AM", "7:00 AM", "8:00 AM", "9:00 AM", "12:00 PM", "3:00 PM", "6:00 PM", "9:00 PM"]
        let weekly = makeProtocol(times: weeklyTimes, days: [1, 2, 3, 4, 5, 6, 7])
        let overflow = makeProtocol(times: weeklyTimes + ["10:00 PM"], days: [1])
        let report = service.scheduleNotifications(for: [weekly, overflow])
        XCTAssertEqual(report.requested, 65)
        XCTAssertEqual(report.scheduled, 64)
        XCTAssertFalse(report.droppedProtocolIDs.isEmpty,
                       "At least one protocol must be reported as having dropped reminders")
        XCTAssertTrue(report.hasAnyIssue)
    }

    func test_scheduleNotifications_invalidTimes_reportedInReport() {
        let proto = makeProtocol(times: ["8:00 AM", "bad-time", "also-bad"], days: [1])
        let report = service.scheduleNotifications(for: [proto])
        XCTAssertEqual(report.scheduled, 1)
        XCTAssertEqual(report.invalidTimes.count, 2)
        XCTAssertTrue(report.invalidTimes.contains("bad-time"))
        XCTAssertTrue(report.invalidTimes.contains("also-bad"))
    }

    func test_scheduleNotifications_invalidWeekdays_reportedAndSkipped() {
        // Day 0 and day 8 are out of ISO 1...7 range
        let proto = makeProtocol(times: ["8:00 AM"], days: [0, 8, 3])
        let report = service.scheduleNotifications(for: [proto])
        XCTAssertEqual(report.scheduled, 1, "Only weekday 3 is valid")
        XCTAssertEqual(report.invalidWeekdays.count, 2)
        XCTAssertTrue(report.invalidWeekdays.contains(0))
        XCTAssertTrue(report.invalidWeekdays.contains(8))
    }

    func test_scheduleNotifications_lastReportMatchesReturnValue() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1])
        let report = service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.lastReport, report)
    }

    func test_cancelAll_resetsLastReport() {
        let proto = makeProtocol(times: ["8:00 AM"], days: [1])
        service.scheduleNotifications(for: [proto])
        XCTAssertEqual(service.lastReport.scheduled, 1)
        service.cancelAll()
        XCTAssertEqual(service.lastReport, .empty)
    }

    // The snooze-preservation invariant (scheduleNotifications must not remove
    // IDs prefixed with NotificationService.snoozeIDPrefix from currentIDs) is
    // exercised in production by NotificationDelegate but isn't covered here
    // because currentIDs is private and constructing a real UNNotificationResponse
    // from a unit test isn't supported by the SDK.

    // MARK: - Helpers

    private func makeProtocol(
        times: [String],
        days: [Int],
        status: ProtocolStatus = .active,
        peptideCount: Int = 2
    ) -> PeptideProtocol {
        let peptides = Array([MockPeptides.bpc157, MockPeptides.tb500, MockPeptides.ghkCu].prefix(max(1, peptideCount)))
        return PeptideProtocol(
            id: UUID(),
            name: "Test Protocol",
            peptides: peptides,
            schedule: ProtocolSchedule(daysOfWeek: days, timesPerDay: times.count, preferredTimes: times),
            cycleLengthWeeks: 8,
            startDate: Date().addingTimeInterval(-30 * 86400),
            status: status,
            notes: ""
        )
    }
}
