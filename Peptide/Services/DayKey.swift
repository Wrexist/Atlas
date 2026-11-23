import Foundation

/// String keys for the local calendar day containing a date, built from
/// the calendar's own year/month/day so they name the day the user saw.
///
/// The three formats are all persisted (UserDefaults, SwiftData, Codable
/// payloads), each by a different feature, so none can change without
/// orphaning stored data. Use the one the stored keys already have.
enum DayKey {
    /// "2026-01-05": supplement taken-days, upsell active days.
    static func dashed(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "20260105": streak-freeze days.
    static func compact(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "2026-1-5": health-journal entries, on-device summary facts, the
    /// perfect-day celebration guard.
    static func unpadded(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
