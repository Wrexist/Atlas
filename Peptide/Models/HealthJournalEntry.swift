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
    var mood: Mood
    var note: String

    init(id: UUID = UUID(), day: Date, mood: Mood, note: String = "") {
        self.id = id
        self.day = day
        self.mood = mood
        self.note = note
    }
}
