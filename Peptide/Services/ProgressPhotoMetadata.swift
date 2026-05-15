import Foundation

/// Read-side helpers for progress-photo metadata. The filename
/// scheme `progress-<unix>-<uuid6>.jpg` was set up so the on-disk
/// list sorts chronologically by name alone — but the timestamp
/// is also semantically useful (date labels in the viewer + diff
/// computation in the compare view), so this helper parses it
/// back out without forcing every caller to scan the prefix.
///
/// Pure-function — no IO. Wraps the date math so a future change
/// to the filename scheme has one place to update.
enum ProgressPhotoMetadata {

    private static let prefix = "progress-"

    /// Extract the wall-clock date encoded in the filename prefix.
    /// Returns nil for any filename that doesn't match the scheme
    /// (legacy filenames, manual additions, etc.) — caller falls
    /// back to file-creation date or "Unknown" in that case.
    static func date(forFilename filename: String) -> Date? {
        guard filename.hasPrefix(prefix) else { return nil }
        let trimmedPrefix = filename.dropFirst(prefix.count)
        // Split on `-` and take the first component (the unix
        // timestamp). The UUID portion may contain hyphens after
        // a future scheme tweak, so be defensive about it.
        guard let firstHyphen = trimmedPrefix.firstIndex(of: "-") else { return nil }
        let stampString = trimmedPrefix[..<firstHyphen]
        guard let stamp = TimeInterval(stampString) else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    /// Number of days between two photos, ignoring time of day.
    /// Powers the "5 days apart" label in the comparison view.
    /// Returns 0 when either date is unparseable.
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let dateA = date(forFilename: a),
              let dateB = date(forFilename: b)
        else { return 0 }
        let calendar = Calendar.current
        let dayA = calendar.startOfDay(for: dateA)
        let dayB = calendar.startOfDay(for: dateB)
        let comps = calendar.dateComponents([.day], from: dayA, to: dayB)
        return abs(comps.day ?? 0)
    }

    /// Pretty date string for the viewer's overlay label. Uses
    /// medium style for "Jan 15, 2026"; switches to relative
    /// phrasing for the most recent week so a today-photo reads
    /// as "Today" rather than the full date.
    static func displayDate(forFilename filename: String, now: Date = Date()) -> String {
        guard let date = date(forFilename: filename) else {
            return String(localized: "Unknown date")
        }
        let interval = now.timeIntervalSince(date)
        let twoDays: TimeInterval = 2 * 24 * 60 * 60
        if interval < twoDays {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: now).capitalized
        }
        return Self.mediumFormatter.string(from: date)
    }

    private static let mediumFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
