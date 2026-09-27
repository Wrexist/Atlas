import Foundation

/// Weekly allowance of AI meal-photo scans on the free tier. Every photo
/// scan is a paid vision call through the proxy, so free users get
/// `freeScansPerWeek` successful scans per ISO week (Monday start, in the
/// user's time zone); Pro is unlimited. Barcode and nutrition-label scans
/// run on-device and are never metered.
///
/// Counts live in UserDefaults under one key per week
/// (`mealScanCount-2026-W39`), so a new week starts at zero without a
/// reset job.
enum MealScanQuota {
    static let freeScansPerWeek = 3
    private static let keyPrefix = "mealScanCount-"

    /// Scans left this week, or `nil` when the user is unlimited.
    static func remaining(count: Int, isPro: Bool) -> Int? {
        guard !isPro else { return nil }
        return max(0, freeScansPerWeek - count)
    }

    /// Storage key for the ISO week containing `date`. ISO rules (Monday
    /// first, week 1 holds the first Thursday) keep the boundary the same
    /// for every locale; only the time zone comes from `calendar`, so the
    /// week turns over at the user's local midnight on Monday.
    static func weekKey(for date: Date, calendar: Calendar) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = parts.yearForWeekOfYear ?? 0
        let week = parts.weekOfYear ?? 0
        return keyPrefix + String(format: "%04d-W%02d", year, week)
    }

    static func count(
        on date: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Int {
        defaults.integer(forKey: weekKey(for: date, calendar: calendar))
    }

    static func remainingThisWeek(
        isPro: Bool,
        on date: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Int? {
        remaining(count: count(on: date, calendar: calendar, defaults: defaults), isPro: isPro)
    }

    /// Called only after a scan came back with items — a failed or empty
    /// scan never spends one of the user's free scans.
    static func recordSuccessfulScan(
        on date: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        let key = weekKey(for: date, calendar: calendar)
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }
}
