import Foundation

extension Array where Element == ProtocolEntry {
    /// Groups entries by `Calendar.current.startOfDay(for: $0.date)`. Used by
    /// DataStore stats and InsightEngine; pre-grouping avoids O(n) re-filtering
    /// inside per-day loops (e.g. 365-day streak calculation).
    var groupedByDay: [Date: [ProtocolEntry]] {
        let calendar = Calendar.current
        return Dictionary(grouping: self) { calendar.startOfDay(for: $0.date) }
    }
}
