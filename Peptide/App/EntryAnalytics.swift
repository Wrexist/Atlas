import Foundation

/// Pure-function read-only stats over `[ProtocolEntry]`. Extracted from
/// `DataStore` so the math is unit-testable in isolation and any future
/// caller (Watch, widget, share card) can reuse the exact same
/// definitions without going through `@MainActor DataStore`.
enum EntryAnalytics {

    /// 7-day completed-vs-scheduled ratio over doses due in the week up
    /// to `now`. A dose scheduled later today is not missed yet, so it
    /// stays out of the window. Returns nil when nothing was due, so
    /// callers can tell "no recent data" from "0%". The window is
    /// computed against `now` so the value drifts as the calendar day
    /// rolls over without needing an explicit cache bust.
    static func weeklyComplianceFraction(
        in entries: [ProtocolEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let window = entries.filter { $0.date >= cutoff && $0.date <= now }
        guard !window.isEmpty else { return nil }
        return Double(window.filter(\.completed).count) / Double(window.count)
    }

    /// Lifetime completed-entry count. Light enough to recompute on every
    /// sync — the array is already in-memory and the watch pipeline
    /// debounces by app activation, not by entry mutation.
    static func totalDosesLogged(in entries: [ProtocolEntry]) -> Int {
        entries.filter(\.completed).count
    }
}
