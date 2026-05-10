import Foundation

/// Date-math helpers for the Track-tab calendar grid. Pure functions over
/// `Calendar` and `Date` so the calendar view stays trivially testable —
/// the grid layout doesn't pull in SwiftUI types.
enum CalendarMonth {

    /// Builds the 6×7 grid of dates that frames the given month. Leading
    /// cells fill in trailing days of the previous month; trailing cells
    /// fill in leading days of the next month — same pattern iOS's own
    /// `UICalendarView` uses. Always 42 entries so every month has the
    /// same row count and the layout doesn't reflow on month change.
    static func grid(
        for monthDate: Date,
        firstWeekday: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        var cal = calendar
        cal.firstWeekday = firstWeekday

        guard let firstOfMonth = cal.date(
            from: cal.dateComponents([.year, .month], from: monthDate)
        ) else { return [] }

        // How many days from the previous month land on the leading row.
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth)
        // Distance from `firstWeekday` to the first-of-month's weekday,
        // wrapped into 0…6. The `+ 7) % 7` covers the EU Mon-start case
        // where weekday == 1 (Sun) and would otherwise go negative.
        let leading = (weekdayOfFirst - firstWeekday + 7) % 7

        let gridStart = cal.date(byAdding: .day, value: -leading, to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: gridStart)
        }
        .map { cal.startOfDay(for: $0) }
    }

    /// Ordered weekday symbols starting at `firstWeekday`. Locale-aware
    /// via `Calendar.shortWeekdaySymbols` so the header reads "Sun Mon …"
    /// in en-US and "Mon Tue …" in en-GB / locales where Mon is the
    /// first day of the week.
    static func weekdaySymbols(
        firstWeekday: Int,
        calendar: Calendar = .current
    ) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let offset = firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

