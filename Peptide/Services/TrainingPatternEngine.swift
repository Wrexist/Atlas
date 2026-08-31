import Foundation

/// Personalization brief Phase 9/10: identifies real, observed
/// training-frequency patterns from a user's own workout history — no
/// fabricated behavioral profiles, just counts and comparisons over
/// actual `WorkoutSession.startedAt` dates the app already records.
///
/// Compares like with like: both the historical baseline and "this week"
/// are trailing 7-day *rolling* windows anchored to `referenceDate`, not
/// calendar weeks — so a Wednesday check and a Sunday check are never
/// penalized just for landing on a different point in a partial calendar
/// week, and the baseline's most recent block ends exactly where the
/// current window begins (no overlap, no gap).
///
/// Pure function: no I/O, no SwiftData dependency. Callers gather the
/// session dates themselves (typically via `SwiftDataRepository`).
enum TrainingPatternEngine {

    static let defaultTrailingWeeks = 8
    static let emergingAtWeeks = 3
    static let establishedAtWeeks = 6

    /// Baseline built from `trailingWeeks` non-overlapping, fully-elapsed
    /// 7-day blocks immediately preceding the current rolling week (see
    /// `currentRollingWeekCount`) — the current week's own days are never
    /// counted inside the baseline that describes what's "normal."
    static func weeklyFrequencyBaseline(
        sessionDates: [Date],
        asOf referenceDate: Date = Date(),
        calendar: Calendar = .current,
        trailingWeeks: Int = defaultTrailingWeeks
    ) -> PersonalBaselineEngine.Baseline? {
        let currentWindowStart = currentRollingWeekStart(asOf: referenceDate, calendar: calendar)
        var counts: [Double] = []
        for weekIndex in 0..<trailingWeeks {
            guard
                let blockEnd = calendar.date(byAdding: .day, value: -7 * weekIndex, to: currentWindowStart),
                let blockStart = calendar.date(byAdding: .day, value: -7, to: blockEnd)
            else { continue }
            let count = sessionDates.filter { $0 >= blockStart && $0 < blockEnd }.count
            counts.append(Double(count))
        }
        return PersonalBaselineEngine.build(
            values: counts,
            emergingAt: emergingAtWeeks,
            establishedAt: establishedAtWeeks
        )
    }

    /// Sessions in the trailing 7 days ending on `referenceDate`,
    /// inclusive of today — the same rolling-window shape the baseline's
    /// blocks use, so the two are always directly comparable.
    static func currentRollingWeekCount(
        sessionDates: [Date],
        asOf referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let windowStart = currentRollingWeekStart(asOf: referenceDate, calendar: calendar)
        let today = calendar.startOfDay(for: referenceDate)
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? referenceDate
        return sessionDates.filter { $0 >= windowStart && $0 < windowEnd }.count
    }

    /// Most-trained ISO weekdays (1=Mon...7=Sun) across all provided
    /// session dates, sorted ascending, ties included. Empty when there's
    /// no data. Purely descriptive — no claim about *why* those days.
    static func preferredWeekdays(sessionDates: [Date], calendar: Calendar = .current) -> [Int] {
        guard !sessionDates.isEmpty else { return [] }
        var counts: [Int: Int] = [:]
        for date in sessionDates {
            let weekday = calendar.component(.weekday, from: date)
            let isoDay = weekday == 1 ? 7 : weekday - 1
            counts[isoDay, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        guard maxCount > 0 else { return [] }
        return counts.filter { $0.value == maxCount }.map(\.key).sorted()
    }

    /// Start of the trailing-7-day rolling window ending on
    /// `referenceDate` — i.e. `referenceDate`'s day minus 6 days.
    private static func currentRollingWeekStart(asOf referenceDate: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today
    }
}
