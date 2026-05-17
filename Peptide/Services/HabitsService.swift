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
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let habitEntries = entries
            .filter { $0.habitId == habit.id && $0.value > 0 }
            .sorted { $0.date < $1.date }

        let today = calendar.startOfDay(for: date)
        let todayEntry = habitEntries.first { calendar.isDate($0.date, inSameDayAs: today) }
        let todayValue = todayEntry?.value ?? 0
        let target = habit.targetValue ?? 1
        let isCompletedToday = todayValue >= target
        let progress = min(1.0, Double(todayValue) / Double(target))

        return Summary(
            habitId: habit.id,
            currentStreak: currentStreak(for: habit, entries: habitEntries, on: today, calendar: calendar),
            bestStreak: bestStreak(for: habit, entries: habitEntries, calendar: calendar),
            totalCompletedDays: completedDays(habit: habit, entries: habitEntries).count,
            isDueToday: habit.schedule.isDue(on: today, calendar: calendar),
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
            let value = entriesById[day]?.first?.value ?? 0
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

    private static func currentStreak(
        for habit: Habit,
        entries: [HabitEntry],
        on today: Date,
        calendar: Calendar
    ) -> Int {
        let completedDays = Set(
            entries
                .filter { $0.value >= (habit.targetValue ?? 1) }
                .map { calendar.startOfDay(for: $0.date) }
        )
        guard !completedDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = today
        // Walk back day-by-day. A non-due day (rest day in a weekday
        // schedule) counts toward the streak only when there's no
        // completion on it — same logic as Streaks.app: gaps on non-
        // due days don't break the chain.
        while true {
            let isDue = habit.schedule.isDue(on: cursor, calendar: calendar)
            if completedDays.contains(cursor) {
                streak += 1
            } else if isDue {
                // Today is allowed to be missing without breaking — a
                // user opening the app at 09:00 hasn't necessarily
                // logged their daily habit yet.
                if calendar.isDate(cursor, inSameDayAs: today) {
                    // skip — don't count, don't break
                } else {
                    break
                }
            }
            // else: not due and not completed → silently skip
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            // Safety: stop after 10 years to avoid pathological loops
            // on a clock-confused device.
            if streak > 3650 { break }
        }
        return streak
    }

    private static func bestStreak(
        for habit: Habit,
        entries: [HabitEntry],
        calendar: Calendar
    ) -> Int {
        let target = habit.targetValue ?? 1
        let completed = entries
            .filter { $0.value >= target }
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()

        guard !completed.isEmpty else { return 0 }

        var best = 1
        var current = 1
        for i in 1..<completed.count {
            let prior = completed[i - 1]
            let next  = completed[i]
            if let between = calendar.dateComponents([.day], from: prior, to: next).day, between == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    private static func completedDays(habit: Habit, entries: [HabitEntry]) -> Set<UUID> {
        let target = habit.targetValue ?? 1
        return Set(entries.filter { $0.value >= target }.map(\.id))
    }
}
