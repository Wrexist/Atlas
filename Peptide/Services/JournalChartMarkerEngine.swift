import Foundation

/// Places health journal days on a biomarker chart's time axis, so a dip
/// in HRV sits next to the day the user wrote "two glasses of wine, late
/// dinner". Pure value-in / value-out so it tests without the store.
enum JournalChartMarkerEngine {

    struct Marker: Equatable, Identifiable, Sendable {
        /// Start of the journal day.
        let day: Date
        let mood: HealthJournalEntry.Mood
        /// First line of the note, cut to `excerptLimit`; nil when empty.
        let excerpt: String?

        var id: Date { day }
    }

    /// Long enough for "Alcohol, late meal, stressful day", short enough
    /// to sit in a chart callout.
    static let excerptLimit = 60

    /// One marker per journal day inside `domain`, oldest first. The
    /// domain's upper bound is exclusive: it is the next day's midnight.
    static func markers(
        from entries: [HealthJournalEntry],
        in domain: ClosedRange<Date>,
        calendar: Calendar
    ) -> [Marker] {
        var seen = Set<Date>()
        return entries
            .map { (day: calendar.startOfDay(for: $0.day), entry: $0) }
            .filter { $0.day >= domain.lowerBound && $0.day < domain.upperBound }
            .sorted { $0.day < $1.day }
            .filter { seen.insert($0.day).inserted }
            .map { Marker(day: $0.day, mood: $0.entry.mood, excerpt: excerpt($0.entry.note)) }
    }

    /// The marker on the same calendar day as `date`, for the scrub callout.
    static func marker(on date: Date, in markers: [Marker], calendar: Calendar) -> Marker? {
        let day = calendar.startOfDay(for: date)
        return markers.first { $0.day == day }
    }

    /// The note's first line, trimmed and cut at a word where it can be.
    static func excerpt(_ note: String) -> String? {
        let firstLine = note
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return nil }
        guard firstLine.count > excerptLimit else { return firstLine }
        let cut = firstLine.prefix(excerptLimit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }
}
