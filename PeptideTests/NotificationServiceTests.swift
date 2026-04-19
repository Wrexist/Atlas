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
