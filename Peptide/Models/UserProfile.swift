import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female, unspecified
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .unspecified: "Prefer not to say"
        }
    }

    /// Compact label used inside narrow chips/segmented controls where the
    /// full "Prefer not to say" wraps awkwardly.
    var shortLabel: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .unspecified: "Skip"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, athlete
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Light"
        case .moderate: "Moderate"
        case .active: "Active"
        case .athlete: "Athlete"
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary: "Desk work, little exercise"
        case .light: "1–2 sessions per week"
        case .moderate: "3–4 sessions per week"
        case .active: "5–6 intense sessions"
        case .athlete: "Daily training, competition"
        }
    }
}

enum MeasurementUnit: String, Codable {
    case metric    // kg, cm
    case imperial  // lb, in
}

/// Optional body metrics used to personalize peptide dose recommendations.
/// All fields are optional — users can skip the metrics step. Stored
/// canonically in metric units; the UI converts on read/write.
struct BodyMetrics: Codable, Hashable {
    var weightKg: Double?
    var heightCm: Double?
    var age: Int?
    var sex: BiologicalSex
    var activityLevel: ActivityLevel
    var unit: MeasurementUnit

    static var unspecified: BodyMetrics {
        BodyMetrics(
            weightKg: nil,
            heightCm: nil,
            age: nil,
            sex: .unspecified,
            activityLevel: .moderate,
            unit: localeDefaultUnit
        )
    }

    /// Falls back to imperial for the four locales that still use it (US,
    /// Liberia, Myanmar) plus the UK where weight in stones/lb is common.
    /// Everywhere else defaults to metric.
    private static var localeDefaultUnit: MeasurementUnit {
        let region = Locale.current.region?.identifier ?? ""
        switch region {
        case "US", "LR", "MM", "GB":
            return .imperial
        default:
            return .metric
        }
    }

    var hasWeight: Bool { weightKg ?? 0 > 0 }
    var hasHeight: Bool { heightCm ?? 0 > 0 }
    var isComplete: Bool { hasWeight && hasHeight && (age ?? 0) > 0 }
}

struct UserProfile: Codable {
    var name: String
    var goals: [String]
    var memberSince: Date
    var healthConnected: Bool
    var hapticFeedbackEnabled: Bool
    var doseRemindersEnabled: Bool
    var biometricLockEnabled: Bool
    var bodyMetrics: BodyMetrics

    init(
        name: String,
        goals: [String],
        memberSince: Date,
        healthConnected: Bool,
        hapticFeedbackEnabled: Bool = true,
        doseRemindersEnabled: Bool = false,
        biometricLockEnabled: Bool = false,
        bodyMetrics: BodyMetrics = .unspecified
    ) {
        self.name = name
        self.goals = goals
        self.memberSince = memberSince
        self.healthConnected = healthConnected
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.doseRemindersEnabled = doseRemindersEnabled
        self.biometricLockEnabled = biometricLockEnabled
        self.bodyMetrics = bodyMetrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        goals = try container.decode([String].self, forKey: .goals)
        memberSince = try container.decode(Date.self, forKey: .memberSince)
        healthConnected = try container.decode(Bool.self, forKey: .healthConnected)
        hapticFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled) ?? true
        doseRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .doseRemindersEnabled) ?? false
        biometricLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .biometricLockEnabled) ?? false
        bodyMetrics = try container.decodeIfPresent(BodyMetrics.self, forKey: .bodyMetrics) ?? .unspecified
    }

    static var fresh: UserProfile {
        UserProfile(
            name: "",
            goals: [],
            memberSince: Date(),
            healthConnected: false
        )
    }
}
