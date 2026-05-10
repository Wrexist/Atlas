import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female, other, unspecified
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .unspecified: "Prefer not to say"
        }
    }

    /// Compact label used inside narrow chips/segmented controls where the
    /// full "Prefer not to say" wraps awkwardly.
    var shortLabel: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .unspecified: "Skip"
        }
    }

    /// Pills shown on the body-stats step. Excludes `.unspecified` because
    /// the step expects an explicit choice — `.other` covers gender-neutral
    /// users without forcing them into a binary.
    static let onboardingChoices: [BiologicalSex] = [.male, .female, .other]
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

/// Optional body metrics displayed alongside the user's compliance trends
/// on the Profile screen. All fields are optional — users can skip the
/// metrics step. Stored canonically in metric units; the UI converts on
/// read/write. PeptideX does NOT use these values to calculate, scale, or
/// recommend any dose.
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

/// Daily macro targets derived from the user's body stats during onboarding
/// and surfaced on the Lifestyle tab. Stored as integers because they're
/// reference targets — the user doesn't need 0.1 g of protein resolution.
struct NutritionTargets: Codable, Hashable {
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int
}

/// Creator attribution captured during onboarding when the user enters a
/// referral code. Persisted on the profile so the install / conversion can
/// be matched against a creator on the (still-to-be-built) backend, and so
/// the paywall can surface the discount the creator's code grants.
///
/// Matching today is local-only against `CreatorCodeService.seeded` —
/// the spec'd Supabase pipeline (creator_codes table, RPC counters,
/// dashboard) is tracked as a follow-up.
struct CreatorAttribution: Codable, Hashable {
    let code: String
    let creatorName: String
    let discountPercent: Int
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
    /// Calorie + macro targets shown on the Lifestyle tab. Populated from
    /// the onboarding daily-targets screen on first run; the user can edit
    /// the numbers later. Optional so older profiles decode cleanly and so
    /// the Lifestyle tab can detect "not yet computed" and re-prompt.
    var nutritionTargets: NutritionTargets?
    /// Set when the user enters a valid creator code on the onboarding
    /// attribution step. Used by the paywall copy to acknowledge the
    /// discount and (eventually) by the backend to count installs /
    /// conversions per creator.
    var creatorAttribution: CreatorAttribution?
    /// JPEG-encoded profile avatar uploaded from the photo library. Stored
    /// inline so the avatar travels with the profile across exports and
    /// iCloud sync. Compressed before save — see DataStore.updateAvatar.
    var avatarImageData: Data?
    /// Optional short personal bio surfaced on the customization sheet and
    /// the profile header. Free-form, capped at ~280 chars in the UI.
    var bio: String
    /// One of `goals`, marked by the user as their headline focus. Surfaced
    /// at the top of the goals card and used by the home tab to feature
    /// matching peptide recommendations. Empty/nil means no pin.
    var primaryGoal: String?

    init(
        name: String,
        goals: [String],
        memberSince: Date,
        healthConnected: Bool,
        hapticFeedbackEnabled: Bool = true,
        doseRemindersEnabled: Bool = false,
        biometricLockEnabled: Bool = false,
        bodyMetrics: BodyMetrics = .unspecified,
        nutritionTargets: NutritionTargets? = nil,
        creatorAttribution: CreatorAttribution? = nil,
        avatarImageData: Data? = nil,
        bio: String = "",
        primaryGoal: String? = nil
    ) {
        self.name = name
        self.goals = goals
        self.memberSince = memberSince
        self.healthConnected = healthConnected
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.doseRemindersEnabled = doseRemindersEnabled
        self.biometricLockEnabled = biometricLockEnabled
        self.bodyMetrics = bodyMetrics
        self.nutritionTargets = nutritionTargets
        self.creatorAttribution = creatorAttribution
        self.avatarImageData = avatarImageData
        self.bio = bio
        self.primaryGoal = primaryGoal
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
        nutritionTargets = try container.decodeIfPresent(NutritionTargets.self, forKey: .nutritionTargets)
        creatorAttribution = try container.decodeIfPresent(CreatorAttribution.self, forKey: .creatorAttribution)
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        bio = try container.decodeIfPresent(String.self, forKey: .bio) ?? ""
        primaryGoal = try container.decodeIfPresent(String.self, forKey: .primaryGoal)
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
