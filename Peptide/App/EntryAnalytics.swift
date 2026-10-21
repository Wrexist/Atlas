import Foundation

/// Pure-function read-only stats over `[ProtocolEntry]`. Extracted from
/// `DataStore` so the math is unit-testable in isolation and any future
/// caller (Watch, widget, share card) can reuse the exact same
/// definitions without going through `@MainActor DataStore`.
enum EntryAnalytics {

    /// 7-day completed-vs-scheduled ratio over the user's full log.
    /// Returns 0 when nothing was scheduled in the window (rather than
    /// NaN) so the watch ring doesn't render an undefined fraction.
    /// The window is computed against `now` so the value drifts as the
    /// calendar day rolls over without needing an explicit cache bust.
    static func weeklyComplianceFraction(
        in entries: [ProtocolEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let window = weeklyWindow(in: entries, now: now, calendar: calendar)
        guard !window.isEmpty else { return 0 }
        return Double(window.filter(\.completed).count) / Double(window.count)
    }

    /// The entries `weeklyComplianceFraction` is measured over, so a
    /// caller can tell "0%" from "nothing scheduled this week".
    static func weeklyWindow(
        in entries: [ProtocolEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProtocolEntry] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return entries.filter { $0.date >= cutoff }
    }

    /// Lifetime completed-entry count. Light enough to recompute on every
    /// sync — the array is already in-memory and the watch pipeline
    /// debounces by app activation, not by entry mutation.
    static func totalDosesLogged(in entries: [ProtocolEntry]) -> Int {
        entries.filter(\.completed).count
    }
}
