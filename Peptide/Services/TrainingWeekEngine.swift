import Foundation

/// The one count every surface compares to the days-per-week target:
/// distinct calendar days with a finished workout, two sessions on one
/// day counting once. Today's ring and checklist, the widget, Train's
/// weekly goal and the weekly check-in all read it, so they agree.
enum TrainingWeekEngine {
    /// Distinct days in `interval` with a workout that started there.
    static func trainedDays(dates: [Date], in interval: Range<Date>, calendar: Calendar) -> Int {
        Set(dates.filter { interval.contains($0) }.map { calendar.startOfDay(for: $0) }).count
    }

    /// Distinct days in `interval` with a finished session; the
    /// in-progress workout isn't logged yet.
    static func trainedDays(_ sessions: [WorkoutSession], in interval: Range<Date>, calendar: Calendar) -> Int {
        trainedDays(
            dates: sessions.filter { !$0.isActive }.map(\.dayAnchor),
            in: interval,
            calendar: calendar
        )
    }

    /// Distinct days with a finished session in the calendar week that
    /// holds `now`.
    static func trainedDaysThisWeek(
        _ sessions: [WorkoutSession], now: Date = Date(), calendar: Calendar = .current
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return trainedDays(sessions, in: week.start..<week.end, calendar: calendar)
    }
}
