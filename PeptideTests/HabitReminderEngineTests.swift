import XCTest
@testable import Peptide

final class HabitReminderEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        c.firstWeekday = 2
        return c
    }()

    /// Monday 2026-10-19 at the given time.
    private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
        october(19, hour, minute)
    }

    /// 2026-10-`day` at the given time; the 19th is a Monday.
    private func october(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
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

    private func plan(_ habits: [Habit], entries: [HabitEntry] = [], now: Date, limit: Int = NotificationService.habitRequestLimit) -> [HabitReminderEngine.Planned] {
        HabitReminderEngine.plan(habits: habits, entries: entries, now: now, calendar: calendar, limit: limit)
    }

    /// Reminders delivered over `days` days if Atlas stayed closed.
    private func fired(_ planned: [HabitReminderEngine.Planned], after now: Date, days: Int) -> [Date] {
        planned.map(\.trigger).fireDates(after: now, days: days, calendar: calendar)
    }

    func test_dailyHabit_notDone_isOneDailyRepeatFromToday() {
        let planned = plan([habit(at: 20)], now: monday(7))
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.trigger.repeats, true)
        XCTAssertEqual(planned.first?.fireDate, monday(20))
    }

    func test_dailyHabit_appNotOpenedForThreeWeeks_keepsReminding() {
        let planned = plan([habit(at: 20)], now: monday(7))
        XCTAssertEqual(fired(planned, after: monday(7), days: 21).count, 21)
    }

    func test_dailyHabit_completedToday_dropsTodayAndKeepsTheRest() {
        let meditate = habit(at: 20)
        let done = HabitEntry(habitId: meditate.id, date: monday(7), calendar: calendar)

        let planned = plan([meditate], entries: [done], now: monday(8))
        let dates = fired(planned, after: monday(8), days: 14)

        XCTAssertFalse(dates.contains { calendar.isDate($0, inSameDayAs: monday(8)) })
        XCTAssertEqual(dates.first, october(20, 20))
        XCTAssertEqual(dates.count, 13)
    }

    func test_countableHabit_belowTargetToday_keepsTodaysReminder() {
        let water = habit(at: 20, target: 8)
        let partial = HabitEntry(habitId: water.id, date: monday(7), value: 3, calendar: calendar)

        let planned = plan([water], entries: [partial], now: monday(8))

        XCTAssertEqual(planned.first?.fireDate, monday(20))
    }

    func test_weekdayHabit_repeatsOnlyOnItsDays() {
        let planned = plan([habit(at: 9, schedule: .weekdays([.tuesday]))], now: monday(7))
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.trigger.repeats, true)
        XCTAssertEqual(planned.first?.trigger.components.weekday, 3)
        XCTAssertEqual(planned.first?.fireDate, october(20, 9))
    }

    func test_timePassedToday_startsTomorrow() {
        let planned = plan([habit(at: 7)], now: monday(9))
        XCTAssertEqual(planned.first?.fireDate, october(20, 7))
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

    func test_overBudget_dropsWholeHabitsNeverSomeOfTheirWeekdays() {
        let first = habit(at: 20)
        let second = habit(at: 21)
        let third = habit(at: 22)
        let done = [first, second].map { HabitEntry(habitId: $0.id, date: monday(7), calendar: calendar) }

        // Done today, the first two take seven slots each.
        let planned = plan([first, second, third], entries: done, now: monday(8), limit: 10)

        XCTAssertEqual(Set(planned.map(\.habit.id)), [first.id, third.id])
        let firstDates = fired(planned.filter { $0.habit.id == first.id }, after: monday(8), days: 14)
        XCTAssertEqual(firstDates.count, 13)
    }

    func test_identifiers_areUniquePerHabitAndSlot_andInHabitNamespace() {
        let weekly = habit(at: 9, schedule: .weekdays([.monday, .wednesday]))
        let planned = plan([habit(at: 9), habit(at: 9), weekly], now: monday(7))
        XCTAssertEqual(planned.count, 4)
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
        // Only Monday collides; the other days keep 08:00.
        XCTAssertEqual(planned.dropFirst().first?.fireDate, october(20, 8))
    }

    func test_timesPerWeekHabit_targetMetThisWeek_silencesRestOfWeek() {
        let lift = habit(at: 18, schedule: .timesPerWeek(2))
        let entries = [19, 20].map { HabitEntry(habitId: lift.id, date: october($0, 7), calendar: calendar) }

        let planned = plan([lift], entries: entries, now: october(21, 8))
        let thisWeek = fired(planned, after: october(21, 8), days: 5)

        XCTAssertTrue(thisWeek.isEmpty)
    }

    func test_timesPerWeekHabit_targetMet_resumesNextWeek() {
        let lift = habit(at: 18, schedule: .timesPerWeek(2))
        let entries = [19, 20].map { HabitEntry(habitId: lift.id, date: october($0, 7), calendar: calendar) }

        let planned = plan([lift], entries: entries, now: october(24, 8))
        let dates = fired(planned, after: october(24, 8), days: 9)

        XCTAssertEqual(dates.first, october(26, 18))
        XCTAssertEqual(dates.count, 7)
    }

    func test_timesPerWeekHabit_belowTarget_keepsReminding() {
        let lift = habit(at: 18, schedule: .timesPerWeek(2))
        let once = HabitEntry(habitId: lift.id, date: october(19, 7), calendar: calendar)

        let planned = plan([lift], entries: [once], now: october(21, 8))

        XCTAssertEqual(planned.first?.fireDate, october(21, 18))
        XCTAssertEqual(fired(planned, after: october(21, 8), days: 5).count, 5)
    }

    func test_timesPerWeekHabit_otherHabitsEntries_doNotCountTowardTarget() {
        let lift = habit(at: 18, schedule: .timesPerWeek(2))
        let entries = [19, 20].map { HabitEntry(habitId: UUID(), date: october($0, 7), calendar: calendar) }

        let planned = plan([lift], entries: entries, now: october(21, 8))

        XCTAssertEqual(planned.first?.fireDate, october(21, 18))
    }
}
