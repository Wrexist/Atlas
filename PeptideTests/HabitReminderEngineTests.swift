import XCTest
@testable import Peptide

final class HabitReminderEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// Monday 2026-10-19 at the given time.
    private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour, minute: minute)) ?? Date()
    }

    private func habit(at hour: Int, schedule: HabitSchedule = .daily, target: Int? = nil) -> Habit {
        Habit(
            name: "Meditate",
            iconSymbol: "leaf.fill",
            tintHex: 0x00FF00,
            schedule: schedule,
            targetValue: target,
            reminderTime: monday(hour)
        )
    }

    private func plan(_ habits: [Habit], entries: [HabitEntry] = [], now: Date, limit: Int = 32) -> [HabitReminderEngine.Planned] {
        HabitReminderEngine.plan(habits: habits, entries: entries, now: now, calendar: calendar, limit: limit)
    }

    func test_dailyHabit_notDone_coversTodayAndLookahead() {
        let planned = plan([habit(at: 20)], now: monday(7))
        XCTAssertEqual(planned.count, HabitReminderEngine.lookaheadDays)
        XCTAssertEqual(planned.first?.fireDate, monday(20))
    }

    func test_dailyHabit_completedToday_dropsTodayAndKeepsTomorrow() {
        let meditate = habit(at: 20)
        let done = HabitEntry(habitId: meditate.id, date: monday(7), calendar: calendar)

        let planned = plan([meditate], entries: [done], now: monday(8))

        XCTAssertFalse(planned.contains { calendar.isDate($0.fireDate, inSameDayAs: monday(8)) })
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: monday(20))
        XCTAssertEqual(planned.first?.fireDate, tomorrow)
        XCTAssertEqual(planned.count, HabitReminderEngine.lookaheadDays - 1)
    }

    func test_countableHabit_belowTargetToday_keepsTodaysReminder() {
        let water = habit(at: 20, target: 8)
        let partial = HabitEntry(habitId: water.id, date: monday(7), value: 3, calendar: calendar)

        let planned = plan([water], entries: [partial], now: monday(8))

        XCTAssertEqual(planned.first?.fireDate, monday(20))
    }

    func test_weekdayHabit_firesOnlyOnItsDays() {
        // Tuesday only; the window is Monday–Wednesday.
        let planned = plan([habit(at: 9, schedule: .weekdays([.tuesday]))], now: monday(7))
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first.map { calendar.component(.weekday, from: $0.fireDate) }, 3)
    }

    func test_timePassedToday_startsTomorrow() {
        let planned = plan([habit(at: 7)], now: monday(9))
        XCTAssertEqual(planned.count, HabitReminderEngine.lookaheadDays - 1)
        XCTAssertFalse(planned.contains { calendar.isDate($0.fireDate, inSameDayAs: monday(9)) })
    }

    func test_habitWithoutReminderTimeOrArchived_plansNothing() {
        var silent = habit(at: 20)
        silent.reminderTime = nil
        var archived = habit(at: 20)
        archived.archived = true
        XCTAssertTrue(plan([silent, archived], now: monday(7)).isEmpty)
    }

    func test_overBudget_keepsTheSoonestReminders() {
        let habits = (0..<5).map { habit(at: 10 + $0) }
        let planned = plan(habits, now: monday(7), limit: 4)
        XCTAssertEqual(planned.count, 4)
        XCTAssertEqual(planned.map(\.fireDate), [monday(10), monday(11), monday(12), monday(13)])
    }

    func test_identifiers_areUniquePerHabitAndDay_andInHabitNamespace() {
        let planned = plan([habit(at: 9), habit(at: 9)], now: monday(7))
        XCTAssertEqual(Set(planned.map(\.id)).count, planned.count)
        XCTAssertTrue(planned.allSatisfy { $0.id.hasPrefix(NotificationService.habitIDPrefix) })
    }

    func test_doseReminderAtTheSameTime_shiftsTheHabitPastIt() {
        let planned = HabitReminderEngine.plan(
            habits: [habit(at: 8)],
            entries: [],
            now: monday(7),
            calendar: calendar,
            occupied: [(weekday: 2, hour: 8, minute: 0)]
        )
        XCTAssertEqual(planned.first?.fireDate, monday(8, NotificationService.crossTypeCooldownMinutes))
    }
}
