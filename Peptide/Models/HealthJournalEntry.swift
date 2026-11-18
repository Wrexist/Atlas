import Foundation

/// One day in the health journal: how the user felt, and in their own
/// words why. Kept beside the Health data it explains, so Ask Atlas can
/// connect "slept badly, stressful week" to a dip in HRV.
struct HealthJournalEntry: Codable, Equatable, Identifiable, Sendable {
    enum Mood: Int, Codable, CaseIterable, Comparable, Sendable {
        case awful = 1, low, okay, good, great

        static func < (lhs: Mood, rhs: Mood) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: UUID
    /// Start of the day the entry is about. One entry per day.
    var day: Date
    /// That day as the calendar named it where it was written
    /// ("2025-10-9"). Entries are matched on this, not on `day`: after a
    /// time-zone change the stored midnight is another instant, and an
    /// instant match would lose today's entry and write a second one.
    let dayKey: String
    var mood: Mood
    var note: String

    init(id: UUID = UUID(), day: Date, mood: Mood, note: String = "", calendar: Calendar = .current) {
        self.id = id
        self.day = day
        self.dayKey = Self.dayKey(for: day, calendar: calendar)
        self.mood = mood
        self.note = note
    }

    /// Year, month and day of `date` in `calendar`, zone-independent once
    /// written.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, dayKey, mood, note
    }

    /// Entries written before `dayKey` existed take it from `day` in the
    /// current calendar, which is how they were matched until now.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        day = try container.decode(Date.self, forKey: .day)
        dayKey = try container.decodeIfPresent(String.self, forKey: .dayKey)
            ?? Self.dayKey(for: day, calendar: .current)
        mood = try container.decode(Mood.self, forKey: .mood)
        note = try container.decode(String.self, forKey: .note)
    }
}
