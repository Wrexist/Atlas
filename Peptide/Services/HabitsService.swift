import Foundation

/// Pure computation over (habits, entries) — current streak, best
/// streak, lifetime completion count, due-today, and the heatmap
/// matrix for a given date range. All static so the call sites read
/// like math, not like an instance dance. Persistence + mutation
/// lives on `DataStore`; this file only derives.
///
/// Calendar / DST handling: every comparison normalises to
/// `startOfDay(for:)` in the current calendar so a late-night tap and
/// an early-morning tap of the same calendar day count once, and a
/// DST transition doesn't visually skip a column in the heatmap.
enum HabitsService {

    // MARK: - Per-habit summary

    struct Summary: Equatable, Sendable {
        let habitId: UUID
        let currentStreak: Int
        let bestStreak: Int
        let totalCompletedDays: Int
        let isDueToday: Bool
        let isCompletedToday: Bool
        let todayValue: Int
        /// Goal completion percentage for the current day, in 0...1.
        /// Boolean habits return 0 or 1; countable habits return
        /// `todayValue / targetValue` clamped to 1.
        let todayProgress: Double
    }

    static func summary(
        for habit: Habit,
        entries: [HabitEntry],
        frozenDayKeys: Set<String> = [],
        on date: Date = Date(),
        allowsMissingDay: Bool = true,
        calendar: Calendar = .current
    ) -> Summary {
        let habitEntries = entries
            .filter { $0.habitId == habit.id && $0.value > 0 }
            .sorted { $0.date < $1.date }

        let today = calendar.startOfDay(for: date)
        // Take the MAX value when multiple same-day entries exist
        // (CloudKit-race duplicate rows) — `heatmap` already does
        // this; the summary path used to take `first`, which could
        // under-report today's progress and flip isCompletedToday
        // false even after a later entry hit target (PR #131 Codex
        // P2).
        let todayValue = habitEntries
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .map(\.value)
            .max() ?? 0
        let target = habit.targetValue ?? 1
        let isCompletedToday = todayValue >= target
        let progress = min(1.0, Double(todayValue) / Double(target))
        let completed = completedDays(habit: habit, entries: habitEntries, calendar: calendar)

        let streaks: (current: Int, best: Int)
        let isDueToday: Bool
        if case .timesPerWeek(let weeklyTarget) = habit.schedule {
            streaks = weeklyStreaks(
                target: weeklyTarget,
                completedDays: completed,
                on: today,
                allowsMissingWeek: allowsMissingDay,
                calendar: calendar
            )
            // Once the week's target is met the habit stops asking for
            // more, so it no longer holds the daily ring open. A day it
            // was ticked still counts as due-and-done.
            let doneThisWeek = completedCount(in: today, completedDays: completed, calendar: calendar)
            isDueToday = isCompletedToday || doneThisWeek < weeklyTarget
        } else {
            let current = currentStreak(
                for: habit,
                completedDays: completed,
                frozenDayKeys: frozenDayKeys,
                on: today,
                allowsMissingDay: allowsMissingDay,
                calendar: calendar
            )
            // A freeze after the last completion extends the live run
            // but not the completion-to-completion walk.
            let best = bestStreak(for: habit, completedDays: completed, frozenDayKeys: frozenDayKeys, calendar: calendar)
            streaks = (current, max(best, current))
            isDueToday = habit.schedule.isDue(on: today, calendar: calendar)
        }

        return Summary(
            habitId: habit.id,
            currentStreak: streaks.current,
            bestStreak: streaks.best,
            totalCompletedDays: completed.count,
            isDueToday: isDueToday,
            isCompletedToday: isCompletedToday,
            todayValue: todayValue,
            todayProgress: progress
        )
    }

    // MARK: - Heatmap matrix

    /// Per-day status used to colour the heatmap grid. `notDue`
    /// renders as a dimmed cell, `due` (not yet completed) as a slot,
    /// `partial` as a 50% opacity tile, and `completed` as a full
    /// tile.
    enum HeatmapStatus: Sendable, Equatable {
        case notDue
        case due
        case partial(Double)   // 0…1 fraction toward target
        case completed
    }

    /// Returns an ordered list of (date, status) tuples covering the
    /// `dayCount` days ending on `endDate` (inclusive). Caller renders
    /// these in a 7-row × N-column grid; the helper at the bottom of
    /// this file does the column-wise reshape.
    static func heatmap(
        for habit: Habit,
        entries: [HabitEntry],
        endDate: Date = Date(),
        dayCount: Int,
        calendar: Calendar = .current
    ) -> [(date: Date, status: HeatmapStatus)] {
        let end = calendar.startOfDay(for: endDate)
        let entriesById = Dictionary(
            grouping: entries.filter { $0.habitId == habit.id && $0.value > 0 },
            by: { calendar.startOfDay(for: $0.date) }
        )
        let target = habit.targetValue ?? 1

        return (0..<dayCount).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let isDue = habit.schedule.isDue(on: day, calendar: calendar)
            // Take the max value per day so a CloudKit race that
            // produces two entries for one day doesn't silently
            // undercount the higher one (audit L2).
            let value = entriesById[day]?.map(\.value).max() ?? 0
            let status: HeatmapStatus
            if value >= target {
                status = .completed
            } else if value > 0 {
                status = .partial(min(1.0, Double(value) / Double(target)))
            } else if isDue {
                status = .due
            } else {
                status = .notDue
            }
            return (day, status)
        }
    }

    /// Reshape a linear day list into a 7-row × N-column matrix
    /// suitable for a `LazyHGrid` render. Index 0 of each column is
    /// the day-of-week of the column's first cell so the visual reads
    /// Mon..Sun from top to bottom (or Sun..Sat, depending on
    /// `firstWeekday`).
    static func heatmapColumns(
        from days: [(date: Date, status: HeatmapStatus)],
        calendar: Calendar = .current
    ) -> [[HeatmapStatus?]] {
        guard let first = days.first?.date else { return [] }
        let firstWeekdayIndex = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7

        var columns: [[HeatmapStatus?]] = []
        var currentColumn: [HeatmapStatus?] = Array(repeating: nil, count: firstWeekdayIndex)
        for day in days {
            currentColumn.append(day.status)
            if currentColumn.count == 7 {
                columns.append(currentColumn)
                currentColumn = []
            }
        }
        if !currentColumn.isEmpty {
            while currentColumn.count < 7 { currentColumn.append(nil) }
            columns.append(currentColumn)
        }
        return columns
    }

    // MARK: - Streak math

    /// Daily and weekday schedules count due days in a row.
    private static func currentStreak(
        for habit: Habit,
        completedDays: Set<Date>,
        frozenDayKeys: Set<String>,
        on today: Date,
        allowsMissingDay: Bool,
        calendar: Calendar
    ) -> Int {
        guard !completedDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = today
        // Walk back day-by-day. A non-due day (rest day in a weekday
        // schedule) counts toward the streak only when there's no
        // completion on it — same logic as Streaks.app: gaps on non-
        // due days don't break the chain.
        // Absolute iteration cap so a `.weekdays(Set())` (empty set,
        // every day is "not due") or a clock-confused device can't
        // spin forever. The original streak > 3650 guard never
        // tripped in that pathological case because streak never
        // incremented (audit L1).
        for _ in 0..<3650 {
            let isDue = habit.schedule.isDue(on: cursor, calendar: calendar)
            if completedDays.contains(cursor) {
                streak += 1
            } else if isDue {
                if !frozenDayKeys.isEmpty, frozenDayKeys.contains(StreakFreezeService.dayKey(for: cursor, calendar: calendar)) {
                    // A used streak-freeze shields this missed due day — it
                    // counts as covered, matching the dose-streak behavior.
                    streak += 1
                } else if !allowsMissingDay || !calendar.isDate(cursor, inSameDayAs: today) {
                    // Today is allowed to be missing without breaking — a
                    // user opening the app at 09:00 hasn't necessarily
                    // logged their daily habit yet. A finished past day
                    // gets no such grace.
                    break
                }
            }
            // else: not due and not completed → silently skip
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: prev)
        }
        return streak
    }

    /// One pass over the completed days in order: a run continues to the
    /// next completion when every due day in between was frozen. Non-due
    /// rest days don't break the chain, so a perfect Mon → Wed → Fri on a
    /// M/W/F habit returns 3, not 1.
    private static func bestStreak(
        for habit: Habit,
        completedDays: Set<Date>,
        frozenDayKeys: Set<String>,
        calendar: Calendar
    ) -> Int {
        let ordered = completedDays.sorted()
        guard var previous = ordered.first else { return 0 }
        var best = 1
        var run = 1
        for day in ordered.dropFirst() {
            let covered = coveredGap(
                after: previous, before: day,
                schedule: habit.schedule, frozenDayKeys: frozenDayKeys, calendar: calendar
            )
            run = covered.map { run + $0 + 1 } ?? 1
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// The number of frozen due days strictly between two completions, or
    /// nil when a due day in the gap was missed without a freeze.
    private static func coveredGap(
        after start: Date,
        before end: Date,
        schedule: HabitSchedule,
        frozenDayKeys: Set<String>,
        calendar: Calendar
    ) -> Int? {
        var frozen = 0
        var cursor = start
        // Bounded so a corrupted date or an empty weekday set can't spin.
        for _ in 0..<3650 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = calendar.startOfDay(for: next)
            if cursor >= end { return frozen }
            guard schedule.isDue(on: cursor, calendar: calendar) else { continue }
            guard frozenDayKeys.contains(StreakFreezeService.dayKey(for: cursor, calendar: calendar)) else { return nil }
            frozen += 1
        }
        return nil
    }

    /// `.timesPerWeek` habits count weeks in a row that reached the target.
    /// The week in progress adds once it's met and, when
    /// `allowsMissingWeek`, doesn't break the streak before then.
    private static func weeklyStreaks(
        target: Int,
        completedDays: Set<Date>,
        on today: Date,
        allowsMissingWeek: Bool,
        calendar: Calendar
    ) -> (current: Int, best: Int) {
        var countsByWeek: [Date: Int] = [:]
        for day in completedDays {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { continue }
            countsByWeek[week, default: 0] += 1
        }
        let metWeeks = Set(countsByWeek.filter { $0.value >= max(target, 1) }.keys)

        var best = 0
        var run = 0
        var previous: Date?
        for week in metWeeks.sorted() {
            let followsPrevious = previous.flatMap { weekStart(after: $0, calendar: calendar) } == week
            run = followsPrevious ? run + 1 : 1
            best = max(best, run)
            previous = week
        }

        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return (0, best) }
        var current = 0
        var cursor: Date? = thisWeek
        if !metWeeks.contains(thisWeek) {
            guard allowsMissingWeek else { return (0, best) }
            cursor = weekStart(before: thisWeek, calendar: calendar)
        }
        while let week = cursor, metWeeks.contains(week) {
            current += 1
            cursor = weekStart(before: week, calendar: calendar)
        }
        return (current, best)
    }

    private static func weekStart(after week: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .weekOfYear, value: 1, to: week)
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }
    }

    private static func weekStart(before week: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .weekOfYear, value: -1, to: week)
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }
    }

    private static func completedCount(in date: Date, completedDays: Set<Date>, calendar: Calendar) -> Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return completedDays.filter { $0 >= interval.start && $0 < interval.end }.count
    }

    /// De-duplicated set of calendar days on which the habit hit
    /// target. Keyed by `startOfDay(for:)` so two entries for the
    /// same day (CloudKit race) don't double-count. The previous
    /// implementation used entry-id as the dedup key, which the
    /// audit's L9 flagged as wrong — `.count` would over-report on
    /// any duplicate row.
    private static func completedDays(
        habit: Habit,
        entries: [HabitEntry],
        calendar: Calendar
    ) -> Set<Date> {
        let target = habit.targetValue ?? 1
        return Set(
            entries
                .filter { $0.value >= target }
                .map { calendar.startOfDay(for: $0.date) }
        )
    }

    /// "X of N this week" engagement gate for `.timesPerWeek` habits.
    /// Daily and `.weekdays` schedules don't have a weekly count — those
    /// callers should keep using the per-day summary (audit Habits L7).
    /// Window is the current ISO week (firstWeekday of `calendar`).
    static func weeklyProgress(
        for habit: Habit,
        entries: [HabitEntry],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> (count: Int, target: Int)? {
        guard case .timesPerWeek(let target) = habit.schedule else { return nil }
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        let count = completedCount(
            in: date,
            completedDays: completedDays(habit: habit, entries: entries, calendar: calendar),
            calendar: calendar
        )
        return (count: min(count, target), target: max(target, 0))
    }

    // MARK: - Consistency

    /// Overall completion rate across `habits` over the trailing `days`
    /// window ending on `endDate`: (completed due-days) / (total due-days),
    /// where a due-day is one (habit, day) pair the schedule marked due and
    /// "completed" means the day's max entry value reached the target.
    /// `.timesPerWeek` habits are excluded — their `isDue` is true every
    /// day, so per-day completion would misrepresent a weekly cadence.
    /// Returns nil when the window had no due-days (avoids a 0/0 reading);
    /// the progress surface treats nil as "not enough data yet".
    ///
    /// `pendingDay` is a day still in progress: its due habits count once
    /// done but aren't missed yet, so a morning doesn't drag the rate down.
    static func completionRate(
        habits: [Habit],
        entries: [HabitEntry],
        days: Int,
        endingOn endDate: Date = Date(),
        pendingDay: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        guard days > 0 else { return nil }
        let scheduled = habits.filter {
            if case .timesPerWeek = $0.schedule { return false }
            return true
        }
        guard !scheduled.isEmpty else { return nil }

        // Pre-index the best value per (habit, day) so the window scan
        // doesn't re-filter the entries array for every cell.
        var bestValue: [ConsistencyKey: Int] = [:]
        for entry in entries where entry.value > 0 {
            let key = ConsistencyKey(habitId: entry.habitId, day: calendar.startOfDay(for: entry.date))
            bestValue[key] = max(bestValue[key] ?? 0, entry.value)
        }

        let end = calendar.startOfDay(for: endDate)
        var due = 0
        var done = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            let isPending = pendingDay.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
            for habit in scheduled where habit.schedule.isDue(on: day, calendar: calendar) {
                let target = habit.targetValue ?? 1
                let isDone = (bestValue[ConsistencyKey(habitId: habit.id, day: day)] ?? 0) >= target
                if isPending && !isDone { continue }
                due += 1
                if isDone { done += 1 }
            }
        }
        guard due > 0 else { return nil }
        return Double(done) / Double(due)
    }

    private struct ConsistencyKey: Hashable {
        let habitId: UUID
        let day: Date
    }
}
