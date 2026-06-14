import Foundation
import SwiftUI

/// A user-defined habit (Morning Workout, Read 20 pages, Drink 8 glasses,
/// 10k steps, …) that the user can tick off on a recurring schedule.
/// Modeled like Bevel / loggd.life — minimal canonical fields, with
/// computed analytics living on `HabitsService`.
///
/// Habits travel on `UserProfile` so they ride CloudKit sync alongside
/// the rest of the user's data. Soft-deletion via `archived` so a
/// streak isn't visually erased the moment the user removes a habit.
struct Habit: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// SF Symbol name. Validated to a curated set at the edit-sheet
    /// boundary so a typo'd raw value doesn't render a blank box.
    var iconSymbol: String
    /// Stored as a 24-bit RGB integer so the on-disk JSON stays
    /// human-readable and Color is reconstructed lazily at the UI edge.
    /// SwiftUI Color isn't Codable on iOS without a custom wrapper.
    var tintHex: UInt32
    var schedule: HabitSchedule
    /// Optional numeric target (8 glasses, 10000 steps, 20 pages).
    /// `nil` means a boolean habit — one tap, done. When set, the
    /// user logs an integer value per day toward the target.
    var targetValue: Int?
    /// Reminder fires at this time on scheduled days. `nil` = no
    /// reminder. Only the hour + minute components are honored; the
    /// date portion is ignored.
    var reminderTime: Date?
    var category: HabitCategory
    let createdAt: Date
    /// Drag-to-reorder sort key. Smaller values sort first.
    var sortIndex: Int
    /// Soft-delete flag. Archived habits stay in storage so a
    /// 321-day streak isn't erased the moment the user taps Delete —
    /// they can un-archive from settings to restore the history.
    var archived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String,
        tintHex: UInt32,
        schedule: HabitSchedule = .daily,
        targetValue: Int? = nil,
        reminderTime: Date? = nil,
        category: HabitCategory = .health,
        createdAt: Date = Date(),
        sortIndex: Int = 0,
        archived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.tintHex = tintHex
        self.schedule = schedule
        self.targetValue = targetValue
        self.reminderTime = reminderTime
        self.category = category
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.archived = archived
    }

    var tint: Color { Color(hex: UInt(tintHex)) }

    /// True for habits with a numeric target (8 glasses, 10k steps).
    /// Drives the editor UI's value-input visibility.
    var isCountable: Bool { targetValue != nil }
}

/// When a habit is "due". Daily is the common case; weekday-specific
/// covers gym splits, and times-per-week supports flexible commitments
/// like "lift 3x/week, any day".
enum HabitSchedule: Codable, Hashable, Sendable {
    case daily
    case weekdays(Set<HabitWeekday>)
    case timesPerWeek(Int)

    var displayName: String {
        switch self {
        case .daily:                          return "Daily"
        case .weekdays(let days):
            if days.count == 7 { return "Daily" }
            if days == Set(HabitWeekday.weekdays) { return "Weekdays" }
            if days == Set(HabitWeekday.weekend) { return "Weekends" }
            return days
                .sorted(by: { $0.calendarOrder < $1.calendarOrder })
                .map(\.shortName)
                .joined(separator: " ")
        case .timesPerWeek(let n):            return "\(n)×/week"
        }
    }

    /// True when the schedule wants the user to tick this habit on
    /// the given calendar day. `.timesPerWeek` always returns true —
    /// the engagement gate is the weekly count, not the specific day.
    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays(let days):
            // Fail closed: an unresolvable weekday should not mark a
            // weekday-scheduled habit due every day.
            return HabitWeekday.from(date: date, calendar: calendar)
                .map { days.contains($0) } ?? false
        case .timesPerWeek:
            return true
        }
    }
}

enum HabitWeekday: Int, Codable, Hashable, Sendable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static let weekdays: [HabitWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend:  [HabitWeekday] = [.saturday, .sunday]

    /// Sunday-first calendar component → enum.
    static func from(date: Date, calendar: Calendar = .current) -> HabitWeekday? {
        HabitWeekday(rawValue: calendar.component(.weekday, from: date))
    }

    var shortName: String {
        switch self {
        case .sunday:    return "S"
        case .monday:    return "M"
        case .tuesday:   return "T"
        case .wednesday: return "W"
        case .thursday:  return "T"
        case .friday:    return "F"
        case .saturday:  return "S"
        }
    }

    var fullName: String {
        switch self {
        case .sunday:    return "Sunday"
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        }
    }

    /// Monday-first ordering for visual sorting of day pills.
    var calendarOrder: Int {
        switch self {
        case .monday:    return 1
        case .tuesday:   return 2
        case .wednesday: return 3
        case .thursday:  return 4
        case .friday:    return 5
        case .saturday:  return 6
        case .sunday:    return 7
        }
    }
}

enum HabitCategory: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case health, fitness, mindfulness, learning, productivity, custom
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .health:        return "Health"
        case .fitness:       return "Fitness"
        case .mindfulness:   return "Mindfulness"
        case .learning:      return "Learning"
        case .productivity:  return "Productivity"
        case .custom:        return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .health:        return "heart.fill"
        case .fitness:       return "figure.run"
        case .mindfulness:   return "leaf.fill"
        case .learning:      return "book.fill"
        case .productivity:  return "checklist"
        case .custom:        return "sparkles"
        }
    }
}

/// One day's worth of progress on one habit. Boolean habits write
/// `value: 1` once; countable habits write the current count toward
/// `Habit.targetValue`. The date is normalized to start-of-day so a
/// late-night tap and an early-morning tap fall in the same bucket.
struct HabitEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let habitId: UUID
    /// Start-of-day timestamp in the user's current calendar.
    let date: Date
    var value: Int
    var notes: String?

    init(
        id: UUID = UUID(),
        habitId: UUID,
        date: Date,
        value: Int = 1,
        notes: String? = nil
    ) {
        self.id = id
        self.habitId = habitId
        // Honor the documented start-of-day contract so a caller that
        // forgets to normalize can't create duplicate same-day entries.
        self.date = Calendar.current.startOfDay(for: date)
        self.value = value
        self.notes = notes
    }
}

/// Hand-curated icon set surfaced in the habit editor's icon picker.
/// Keeps the set small so the user picks quickly instead of paging
/// through 4000 SF Symbols.
enum HabitIconCatalog {
    static let all: [String] = [
        // fitness
        "figure.strengthtraining.traditional", "figure.run", "figure.yoga", "figure.cooldown",
        "dumbbell.fill", "sportscourt.fill", "figure.pool.swim", "bicycle",
        // wellness
        "drop.fill", "leaf.fill", "moon.zzz.fill", "bed.double.fill",
        "heart.fill", "lungs.fill", "brain.head.profile.fill", "pills.fill",
        // learning / mind
        "book.fill", "graduationcap.fill", "lightbulb.fill", "headphones",
        "mic.fill", "pencil.and.outline",
        // productivity
        "checkmark.circle.fill", "list.bullet.rectangle.fill", "calendar", "clock.fill",
        // misc
        "sparkles", "sun.max.fill", "flame.fill", "bolt.fill",
        "shoeprints.fill", "fork.knife",
    ]
}

/// Hand-curated tint set surfaced in the editor's color picker. Hex
/// values are stored as UInt32 on the `Habit` struct.
enum HabitTintCatalog {
    static let all: [UInt32] = [
        0xCF7272, // red
        0xE89BC4, // pink
        0xC59FFF, // violet
        0x9B72CF, // purple
        0x6B8AFF, // blue
        0x4CB8C4, // cyan
        0x5BC489, // green
        0xD4A844, // amber
        0xFFB347, // orange
        0xCFA68B, // brown
        0x8E9499, // graphite
    ]
}
