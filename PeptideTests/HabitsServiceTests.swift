import XCTest
@testable import Peptide

/// Pins the streak math + heatmap reshape behaviour on
/// `HabitsService`. The service is pure-functional so tests construct
/// fixture habits + entry arrays and assert on the derived values.
@MainActor
final class HabitsServiceTests: XCTestCase {

    private let calendar = Calendar.current

    private func day(_ offset: Int, from base: Date = Date()) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: base) ?? base)
    }

    private func makeHabit(target: Int? = nil, schedule: HabitSchedule = .daily) -> Habit {
        Habit(
            id: UUID(),
            name: "Test",
            iconSymbol: "checkmark.circle.fill",
            tintHex: 0x5BC489,
            schedule: schedule,
            targetValue: target
        )
    }

    // MARK: - Boolean habit streaks

    func test_currentStreak_zero_whenNoEntries() {
        let habit = makeHabit()
        let summary = HabitsService.summary(for: habit, entries: [])
        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertEqual(summary.bestStreak, 0)
        XCTAssertEqual(summary.totalCompletedDays, 0)
    }

    func test_currentStreak_threeConsecutiveDays_endingToday() {
        let habit = makeHabit()
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0)),
            HabitEntry(habitId: habit.id, date: day(1)),
            HabitEntry(habitId: habit.id, date: day(2)),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.currentStreak, 3)
    }

    func test_currentStreak_unloggedToday_doesNotBreakStreak() {
        // A user opens the app at 09:00 with yesterday & before logged.
        // Today is not yet logged but shouldn't reset their streak.
        let habit = makeHabit()
        let entries = [
            HabitEntry(habitId: habit.id, date: day(1)),
            HabitEntry(habitId: habit.id, date: day(2)),
            HabitEntry(habitId: habit.id, date: day(3)),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.currentStreak, 3)
    }

    func test_currentStreak_gapBreaksStreak() {
        let habit = makeHabit()
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0)),
            HabitEntry(habitId: habit.id, date: day(1)),
            // day 2 missing
            HabitEntry(habitId: habit.id, date: day(3)),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.currentStreak, 2)
    }

    func test_bestStreak_picksTheLongestRun() {
        let habit = makeHabit()
        let entries = [
            HabitEntry(habitId: habit.id, date: day(10)),
            HabitEntry(habitId: habit.id, date: day(9)),
            HabitEntry(habitId: habit.id, date: day(8)),
            HabitEntry(habitId: habit.id, date: day(7)),
            HabitEntry(habitId: habit.id, date: day(6)),
            // gap
            HabitEntry(habitId: habit.id, date: day(2)),
            HabitEntry(habitId: habit.id, date: day(1)),
            HabitEntry(habitId: habit.id, date: day(0)),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.bestStreak, 5)
        XCTAssertEqual(summary.currentStreak, 3)
    }

    // MARK: - Countable habits

    func test_countableHabit_belowTarget_doesNotCountAsCompleted() {
        let habit = makeHabit(target: 8)
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0), value: 5),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertFalse(summary.isCompletedToday)
        XCTAssertEqual(summary.todayValue, 5)
        XCTAssertEqual(summary.todayProgress, 5.0 / 8.0, accuracy: 0.001)
    }

    func test_countableHabit_atTarget_countsAsCompleted() {
        let habit = makeHabit(target: 8)
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0), value: 8),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertTrue(summary.isCompletedToday)
        XCTAssertEqual(summary.todayProgress, 1.0)
    }

    func test_countableHabit_overTarget_clampsProgressToOne() {
        let habit = makeHabit(target: 8)
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0), value: 15),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.todayProgress, 1.0)
    }

    // MARK: - Heatmap

    func test_heatmap_returnsDayCountTuples() {
        let habit = makeHabit()
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0)),
            HabitEntry(habitId: habit.id, date: day(5)),
        ]
        let days = HabitsService.heatmap(for: habit, entries: entries, dayCount: 30)
        XCTAssertEqual(days.count, 30)
        // Last entry is today
        XCTAssertTrue(calendar.isDate(days.last!.date, inSameDayAs: Date()))
        // Today is completed
        if case .completed = days.last!.status { } else {
            XCTFail("Expected today to be completed")
        }
    }

    func test_heatmapColumns_padsFirstColumnToSevenRows() {
        let habit = makeHabit()
        let days = HabitsService.heatmap(for: habit, entries: [], dayCount: 30)
        let columns = HabitsService.heatmapColumns(from: days)
        XCTAssertGreaterThan(columns.count, 0)
        for column in columns {
            XCTAssertEqual(column.count, 7, "Every column should be padded to 7 rows")
        }
    }

    // MARK: - Schedule due-date math

    func test_dailySchedule_isAlwaysDue() {
        let schedule: HabitSchedule = .daily
        XCTAssertTrue(schedule.isDue(on: Date()))
        XCTAssertTrue(schedule.isDue(on: Date().addingTimeInterval(60 * 60 * 24 * 7)))
    }

    func test_weekdaySchedule_isDueOnlyOnConfiguredDays() {
        // Pin a Monday for the test (Jan 6 2025 is a Monday).
        let monday = DateComponents(calendar: .current, year: 2025, month: 1, day: 6).date!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let schedule = HabitSchedule.weekdays(Set([.monday, .wednesday, .friday]))
        XCTAssertTrue(schedule.isDue(on: monday))
        XCTAssertFalse(schedule.isDue(on: tuesday))
    }

    func test_timesPerWeekSchedule_isAlwaysDue() {
        // The weekly count is enforced at the engagement layer, not
        // the per-day due check.
        let schedule = HabitSchedule.timesPerWeek(3)
        XCTAssertTrue(schedule.isDue(on: Date()))
    }
}
