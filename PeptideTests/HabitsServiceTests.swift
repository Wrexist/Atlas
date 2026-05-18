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

    // MARK: - bestStreak across rest days (regression — audit H1)

    func test_bestStreak_skipsRestDays_forWeekdaySchedule() {
        // M/W/F schedule, perfect six-completion run:
        // Mon, Wed, Fri, Mon, Wed, Fri across two weeks should
        // report best = 6, not 1 (the old impl required day
        // gaps of exactly 1).
        let habit = makeHabit(
            schedule: .weekdays(Set([.monday, .wednesday, .friday]))
        )
        // Find the last Mon/Wed/Fri sequence relative to today
        // and seed completions on those days. Easier: explicitly
        // construct ten consecutive M/W/F days going back.
        let calendar = Calendar.current
        var dueDays: [Date] = []
        var cursor = calendar.startOfDay(for: Date())
        while dueDays.count < 6 {
            if let weekday = HabitWeekday.from(date: cursor),
               [.monday, .wednesday, .friday].contains(weekday) {
                dueDays.append(cursor)
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        let entries = dueDays.map { HabitEntry(habitId: habit.id, date: $0, value: 1) }
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.bestStreak, 6,
                       "bestStreak should walk across rest days for weekday-scheduled habits")
    }

    func test_bestStreak_zero_whenNoCompletions() {
        let habit = makeHabit(schedule: .weekdays(Set([.monday])))
        let summary = HabitsService.summary(for: habit, entries: [])
        XCTAssertEqual(summary.bestStreak, 0)
    }

    // MARK: - Countable habit streak (audit H4)

    func test_countableHabit_streak_onlyCountsTargetHitDays() {
        let habit = makeHabit(target: 8)
        let entries = [
            HabitEntry(habitId: habit.id, date: day(2), value: 8),  // hit
            HabitEntry(habitId: habit.id, date: day(1), value: 5),  // partial
            HabitEntry(habitId: habit.id, date: day(0), value: 8),  // hit
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        // Day 1's partial doesn't count as a completion, so the
        // current streak from "today's hit" walks back, finds
        // yesterday wasn't a hit, and stops at 1.
        XCTAssertEqual(summary.currentStreak, 1)
        XCTAssertEqual(summary.totalCompletedDays, 2)
    }

    // MARK: - Duplicate-entry dedup (audit L9)

    func test_totalCompletedDays_dedupesDuplicates() {
        // Simulate a CloudKit race where two devices wrote the
        // same day's completion. The total should count once.
        let habit = makeHabit()
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0), value: 1),
            HabitEntry(habitId: habit.id, date: day(0), value: 1),
        ]
        let summary = HabitsService.summary(for: habit, entries: entries)
        XCTAssertEqual(summary.totalCompletedDays, 1)
    }

    // MARK: - Heatmap dedup (audit L2)

    func test_heatmap_takesMaxValuePerDay_onDuplicateEntries() {
        let habit = makeHabit(target: 8)
        // Two entries for today — one above target, one below.
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0), value: 3),
            HabitEntry(habitId: habit.id, date: day(0), value: 8),
        ]
        let days = HabitsService.heatmap(for: habit, entries: entries, dayCount: 5)
        guard case .completed = days.last!.status else {
            XCTFail("Expected today to be completed via max-value dedup")
            return
        }
    }

    // MARK: - Empty input

    func test_heatmap_emptyEntries_marksAllDaysAsDue() {
        let habit = makeHabit()
        let days = HabitsService.heatmap(for: habit, entries: [], dayCount: 5)
        XCTAssertEqual(days.count, 5)
        for entry in days {
            if case .due = entry.status { } else {
                XCTFail("Expected all days to render .due for an empty entry list, got \(entry.status)")
            }
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

    // MARK: - weeklyProgress (audit Habits L7)

    func test_weeklyProgress_nil_forNonTimesPerWeekSchedules() {
        let daily = makeHabit(schedule: .daily)
        XCTAssertNil(HabitsService.weeklyProgress(for: daily, entries: []))
        let weekdays = makeHabit(schedule: .weekdays(Set([.monday])))
        XCTAssertNil(HabitsService.weeklyProgress(for: weekdays, entries: []))
    }

    func test_weeklyProgress_countsCompletionsInCurrentWeek() {
        let habit = makeHabit(schedule: .timesPerWeek(3))
        // Anchor inside the current week to dodge week-boundary
        // flakiness — three completions across the last 3 days.
        let entries = [
            HabitEntry(habitId: habit.id, date: day(0), value: 1),
            HabitEntry(habitId: habit.id, date: day(1), value: 1),
            HabitEntry(habitId: habit.id, date: day(2), value: 1),
        ]
        let progress = HabitsService.weeklyProgress(for: habit, entries: entries)
        XCTAssertNotNil(progress)
        // Some of the 3 days may fall in the previous calendar week
        // if today is early in the week; we expect ≤3 with at least 1.
        XCTAssertGreaterThanOrEqual(progress?.count ?? 0, 1)
        XCTAssertLessThanOrEqual(progress?.count ?? 0, 3)
        XCTAssertEqual(progress?.target, 3)
    }

    func test_weeklyProgress_capsAtTarget() {
        let habit = makeHabit(schedule: .timesPerWeek(2))
        // Five completions, target is 2 — count clamps so the
        // "X of N" badge can't display "5 of 2".
        let entries = (0..<5).map {
            HabitEntry(habitId: habit.id, date: day($0), value: 1)
        }
        let progress = HabitsService.weeklyProgress(for: habit, entries: entries)
        XCTAssertEqual(progress?.target, 2)
        XCTAssertLessThanOrEqual(progress?.count ?? 99, 2)
    }
}
