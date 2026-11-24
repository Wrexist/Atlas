import XCTest
@testable import Peptide

final class DoseReminderTriggerTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// 2026-10-`day` at the given time; the 19th is a Monday.
    private func october(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func mondayAtEight(now: Date, logged: [Date]) -> ReminderTriggerEngine.Trigger? {
        NotificationService.weeklyDoseTrigger(weekday: 2, hour: 8, minute: 0, now: now, calendar: calendar) { date in
            logged.contains { calendar.isDate($0, equalTo: date, toGranularity: .minute) }
        }
    }

    func test_weeklySlot_nothingLogged_repeatsWeekly() {
        let planned = mondayAtEight(now: october(19, 7), logged: [])

        XCTAssertEqual(planned?.repeats, true)
        XCTAssertEqual(planned?.nextFireDate, october(19, 8))
        XCTAssertEqual(planned?.components, DateComponents(hour: 8, minute: 0, weekday: 2))
    }

    func test_weeklySlot_loggedEarlierToday_skipsTodayAndFiresNextWeek() {
        let planned = mondayAtEight(now: october(19, 7), logged: [october(19, 8)])

        XCTAssertEqual(planned?.repeats, false)
        XCTAssertEqual(planned?.nextFireDate, october(26, 8))
    }

    func test_weeklySlot_reminderTimeAlreadyPassed_keepsRepeating() {
        // Today's occurrence is behind us, so the log no longer matters.
        let planned = mondayAtEight(now: october(19, 9), logged: [october(19, 8)])

        XCTAssertEqual(planned?.repeats, true)
        XCTAssertEqual(planned?.nextFireDate, october(26, 8))
    }

    func test_weeklySlot_skipAcrossDaylightSavingEnd_keepsWallClockTime() {
        // Central European summer time ends on Sunday 2026-10-25.
        let planned = mondayAtEight(now: october(19, 7), logged: [october(19, 8)])

        XCTAssertEqual(planned.map { calendar.component(.hour, from: $0.nextFireDate) }, 8)
        XCTAssertEqual(planned?.components.hour, 8)
        XCTAssertEqual(planned?.components.day, 26)
    }

    func test_doseSlotKey_sameProtocolAndMinute_matches() {
        let id = UUID()
        XCTAssertEqual(
            NotificationService.doseSlotKey(protocolID: id, date: october(19, 8), calendar: calendar),
            NotificationService.doseSlotKey(protocolID: id, date: october(19, 8).addingTimeInterval(30), calendar: calendar)
        )
    }

    func test_doseSlotKey_otherDayOrProtocol_differs() {
        let id = UUID()
        let today = NotificationService.doseSlotKey(protocolID: id, date: october(19, 8), calendar: calendar)
        XCTAssertNotEqual(today, NotificationService.doseSlotKey(protocolID: id, date: october(20, 8), calendar: calendar))
        XCTAssertNotEqual(today, NotificationService.doseSlotKey(protocolID: UUID(), date: october(19, 8), calendar: calendar))
    }

    private func everyThreeDays(anchor: Date?) -> ProtocolSchedule {
        ProtocolSchedule(daysOfWeek: [], timesPerDay: 1, preferredTimes: ["8:00 AM"], intervalDays: 3, intervalAnchor: anchor)
    }

    func test_firstIntervalDay_noAnchor_countsFromProtocolStart() {
        // Started Monday the 19th: dose days are the 19th, 22nd, 25th...
        let first = NotificationService.firstIntervalDay(
            everyThreeDays(anchor: nil),
            protocolStart: october(19, 0),
            onOrAfter: october(21, 7),
            calendar: calendar
        )
        XCTAssertEqual(first, october(22, 0))
    }

    func test_firstIntervalDay_noAnchor_matchesTodayAndDoseCalendar() {
        let schedule = everyThreeDays(anchor: nil)
        let first = NotificationService.firstIntervalDay(
            schedule,
            protocolStart: october(19, 0),
            onOrAfter: october(21, 7),
            calendar: calendar
        )
        XCTAssertEqual(first.map { schedule.isActive(on: $0, protocolStart: october(19, 0), calendar: calendar) }, true)
    }

    func test_firstIntervalDay_storedAnchor_winsOverProtocolStart() {
        let first = NotificationService.firstIntervalDay(
            everyThreeDays(anchor: october(20, 0)),
            protocolStart: october(19, 0),
            onOrAfter: october(21, 7),
            calendar: calendar
        )
        XCTAssertEqual(first, october(23, 0))
    }

    func test_firstIntervalDay_futureStart_returnsStartDay() {
        let first = NotificationService.firstIntervalDay(
            everyThreeDays(anchor: nil),
            protocolStart: october(24, 0),
            onOrAfter: october(21, 7),
            calendar: calendar
        )
        XCTAssertEqual(first, october(24, 0))
    }
}
