import XCTest
@testable import Peptide

final class ReminderTriggerEngineTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// 2026-10-`day` at the given time; the 19th is a Monday.
    private func october(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func slots(_ weekdays: [Int] = Array(1...7), hour: Int = 20) -> [ReminderTriggerEngine.Slot] {
        weekdays.map { ReminderTriggerEngine.Slot(weekday: $0, hour: hour, minute: 0) }
    }

    private func triggers(
        _ slots: [ReminderTriggerEngine.Slot],
        now: Date,
        skipping skipped: [Date] = []
    ) -> [ReminderTriggerEngine.Trigger] {
        ReminderTriggerEngine.triggers(for: slots, now: now, calendar: calendar) { date in
            skipped.contains { calendar.isDate($0, inSameDayAs: date) }
        }
    }

    func test_everyDaySameTime_nothingSkipped_isOneDailyRepeat() {
        let planned = triggers(slots(), now: october(19, 7))

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.repeats, true)
        XCTAssertEqual(planned.first?.components, DateComponents(hour: 20, minute: 0))
        XCTAssertEqual(planned.first?.nextFireDate, october(19, 20))
    }

    func test_timePassedToday_dailyRepeatNextFiresTomorrow() {
        let planned = triggers(slots(), now: october(19, 21))

        XCTAssertEqual(planned.first?.nextFireDate, october(20, 20))
    }

    func test_appNotOpenedForThreeWeeks_everyDayStillFires() {
        let now = october(19, 7)
        let fired = triggers(slots(), now: now).fireDates(after: now, days: 21, calendar: calendar)

        XCTAssertEqual(fired.count, 21)
        XCTAssertEqual(fired.last.map { calendar.component(.day, from: $0) }, 8)
    }

    func test_todaySkipped_splitsIntoWeekdayRepeatsAndOneShotNextWeek() {
        let planned = triggers(slots(), now: october(19, 7), skipping: [october(19, 7)])

        XCTAssertEqual(planned.count, 7)
        XCTAssertEqual(planned.filter(\.repeats).count, 6)
        let oneShot = planned.first { !$0.repeats }
        // Summer time ends on the 25th; the one-shot keeps 20:00 local.
        XCTAssertEqual(oneShot?.nextFireDate, october(26, 20))
        XCTAssertEqual(oneShot?.key, "w2")
    }

    func test_todaySkipped_appNotOpenedForTwoWeeks_onlyTodayIsSilent() {
        let now = october(19, 7)
        let fired = triggers(slots(), now: now, skipping: [now]).fireDates(after: now, days: 14, calendar: calendar)

        XCTAssertEqual(fired.count, 13)
        XCTAssertFalse(fired.contains { calendar.isDate($0, inSameDayAs: now) })
        XCTAssertEqual(fired.first, october(20, 20))
    }

    func test_weekdaySubset_isOneRepeatPerWeekday_soonestFirst() {
        // Calendar weekdays 3 and 5: Tuesday and Thursday.
        let planned = triggers(slots([5, 3]), now: october(19, 7))

        XCTAssertEqual(planned.map(\.key), ["w3", "w5"])
        XCTAssertTrue(planned.allSatisfy(\.repeats))
        XCTAssertEqual(planned.map(\.nextFireDate), [october(20, 20), october(22, 20)])
    }

    func test_timesDifferByWeekday_staysPerWeekday() {
        var mixed = slots(Array(1...6))
        mixed.append(ReminderTriggerEngine.Slot(weekday: 7, hour: 9, minute: 0))

        let planned = triggers(mixed, now: october(19, 7))

        XCTAssertEqual(planned.count, 7)
        XCTAssertFalse(planned.contains { $0.key == "everyday" })
    }

    func test_noSlots_plansNothing() {
        XCTAssertTrue(triggers([], now: october(19, 7)).isEmpty)
    }
}
