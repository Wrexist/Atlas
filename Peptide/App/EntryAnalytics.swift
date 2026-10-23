import Foundation

/// Pure-function read-only stats over `[ProtocolEntry]`. Extracted from
/// `DataStore` so the math is unit-testable in isolation and any future
/// caller (Watch, widget, share card) can reuse the exact same
/// definitions without going through `@MainActor DataStore`.
enum EntryAnalytics {

    /// Completed ÷ due doses over the last 7 calendar days, pooled across
    /// `protocols` with the same definition the protocol screen uses
    /// (`PeptideProtocol.adherenceCounts`): a scheduled day the app never
    /// generated entries for counts as missed, a dose later today is not
    /// missed yet, and wash-out days have nothing due. Nil when nothing
    /// was due, so callers can tell "no recent data" from "0%".
    static func weeklyComplianceFraction(
        in entries: [ProtocolEntry],
        protocols: [PeptideProtocol],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let counts = protocols.map {
            $0.adherenceCounts(entries: entries, days: 7, now: now, calendar: calendar)
        }
        let due = counts.reduce(0) { $0 + $1.due }
        guard due > 0 else { return nil }
        let completed = counts.reduce(0) { $0 + $1.completed }
        return Double(completed) / Double(due)
    }

    /// Lifetime completed-entry count. Light enough to recompute on every
    /// sync — the array is already in-memory and the watch pipeline
    /// debounces by app activation, not by entry mutation.
    static func totalDosesLogged(in entries: [ProtocolEntry]) -> Int {
        entries.filter(\.completed).count
    }
}
