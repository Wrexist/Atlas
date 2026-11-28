import Foundation

/// When to write an automatic restore point and which ones to keep.
/// Pure so the retention rules can be tested without touching disk;
/// `RestorePointService` does the file work.
///
/// Retention: the newest point of each of the 7 most recent days, plus
/// the newest point of each of the 8 most recent weeks. That is at most
/// 15 files and reaches about two months back, so a bug noticed weeks
/// later still has a clean copy from before it.
enum RestorePointEngine {
    static let minimumInterval: TimeInterval = 24 * 60 * 60
    static let dailyPointsKept = 7
    static let weeklyPointsKept = 8

    /// A new point is due when none exists or the newest is a day old.
    /// A newest point dated in the future (clock moved back) counts as
    /// due too, so a wrong clock can't stop restore points for good.
    static func isDue(latest: Date?, now: Date) -> Bool {
        guard let latest else { return true }
        let age = now.timeIntervalSince(latest)
        return age >= minimumInterval || age < 0
    }

    /// The dates to keep out of `dates`; every other point is deleted.
    static func datesToKeep(_ dates: [Date], calendar: Calendar) -> Set<Date> {
        let newestFirst = dates.sorted(by: >)
        let daily = newestPerBucket(newestFirst, limit: dailyPointsKept) {
            calendar.dateComponents([.year, .month, .day], from: $0)
        }
        let weekly = newestPerBucket(newestFirst, limit: weeklyPointsKept) {
            calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0)
        }
        return daily.union(weekly)
    }

    /// Walks newest first and takes the first date of each new bucket,
    /// stopping after `limit` buckets.
    private static func newestPerBucket(
        _ newestFirst: [Date],
        limit: Int,
        bucket: (Date) -> DateComponents
    ) -> Set<Date> {
        var seen: Set<DateComponents> = []
        var kept: Set<Date> = []
        for date in newestFirst {
            let key = bucket(date)
            guard !seen.contains(key) else { continue }
            guard seen.count < limit else { break }
            seen.insert(key)
            kept.insert(date)
        }
        return kept
    }
}
