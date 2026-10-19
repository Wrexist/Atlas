import Foundation

/// The everyday nudges that keep the logging loop going — the three main
/// meals, the training-day reminder, and the morning weigh-in. Each fires
/// at most once a day and is skipped when the thing it nudges for is
/// already logged (see `DailyReminderEngine`).
enum DailyReminderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case weighIn, breakfast, lunch, dinner, workout

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weighIn:   String(localized: "Morning weigh-in", comment: "Daily reminder — log bodyweight")
        case .breakfast: MealCategory.breakfast.displayName
        case .lunch:     MealCategory.lunch.displayName
        case .dinner:    MealCategory.dinner.displayName
        case .workout:   String(localized: "Training days", comment: "Daily reminder — workout on planned training days")
        }
    }

    var systemImage: String {
        switch self {
        case .weighIn:   "scalemass.fill"
        case .breakfast: "sunrise.fill"
        case .lunch:     "sun.max.fill"
        case .dinner:    "moon.stars.fill"
        case .workout:   "dumbbell.fill"
        }
    }

    /// The meal a reminder is about, or nil for the non-meal kinds.
    var mealCategory: MealCategory? {
        switch self {
        case .breakfast: .breakfast
        case .lunch:     .lunch
        case .dinner:    .dinner
        case .weighIn, .workout: nil
        }
    }
}

/// Which daily reminders are on and when they fire.
///
/// Device-local (UserDefaults), not on the CloudKit-synced profile: a
/// reminder is a property of the phone that buzzes, and syncing it would
/// make an iPad and an iPhone both nag for the same lunch.
struct DailyReminderSettings: Codable, Equatable, Sendable {
    struct Slot: Codable, Equatable, Sendable {
        var isEnabled: Bool
        var hour: Int
        var minute: Int
    }

    var slots: [DailyReminderKind: Slot]

    func slot(_ kind: DailyReminderKind) -> Slot {
        slots[kind] ?? Self.defaultSlot(kind, training: nil)
    }

    var hasAnyEnabled: Bool {
        DailyReminderKind.allCases.contains { slot($0).isEnabled }
    }

    /// Everything off; times picked so switching one on lands somewhere
    /// sensible without a trip to the time picker. The workout time
    /// follows the time of day chosen in onboarding.
    static func defaults(training: TrainingPreferences?) -> DailyReminderSettings {
        DailyReminderSettings(
            slots: Dictionary(uniqueKeysWithValues: DailyReminderKind.allCases.map {
                ($0, defaultSlot($0, training: training))
            })
        )
    }

    private static func defaultSlot(_ kind: DailyReminderKind, training: TrainingPreferences?) -> Slot {
        switch kind {
        case .weighIn:   Slot(isEnabled: false, hour: 7, minute: 30)
        case .breakfast: Slot(isEnabled: false, hour: 8, minute: 30)
        case .lunch:     Slot(isEnabled: false, hour: 12, minute: 30)
        case .dinner:    Slot(isEnabled: false, hour: 19, minute: 0)
        case .workout:
            switch training?.timeOfDay ?? .anytime {
            case .morning:           Slot(isEnabled: false, hour: 7, minute: 0)
            case .midday:            Slot(isEnabled: false, hour: 11, minute: 30)
            case .evening, .anytime: Slot(isEnabled: false, hour: 17, minute: 0)
            }
        }
    }

    // MARK: - Persistence

    private static let defaultsKey = "atlas.dailyReminders.v1"

    static func load(training: TrainingPreferences?, defaults: UserDefaults = .standard) -> DailyReminderSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(DailyReminderSettings.self, from: data)
        else {
            return .defaults(training: training)
        }
        return stored
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
