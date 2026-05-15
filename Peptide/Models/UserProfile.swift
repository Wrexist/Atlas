import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum MeasurementUnit: String, Codable, Sendable {
    case metric    // kg, cm
    case imperial  // lb, in
}

/// Optional body metrics displayed alongside the user's compliance trends
/// on the Profile screen. All fields are optional — users can skip the
/// metrics step. Stored canonically in metric units; the UI converts on
/// read/write. Atlas does NOT use these values to calculate, scale, or
/// recommend any dose.
struct BodyMetrics: Codable, Hashable, Sendable {
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
struct NutritionTargets: Codable, Hashable, Sendable {
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
struct CreatorAttribution: Codable, Hashable, Sendable {
    let code: String
    let creatorName: String
    let discountPercent: Int
}

/// Email captured during the onboarding mailing-list step. Stored locally
/// so the address survives a relaunch; pushing it to the spec'd
/// `email_subscribers` Supabase table + Resend welcome email + 7-day
/// pg_cron retargeting is a separate piece of work that needs the
/// backend in place. The local record carries enough context that the
/// eventual sync job can replay the row 1:1 from this struct.
struct EmailSubscription: Codable, Hashable, Sendable {
    let email: String
    let capturedAt: Date
}

/// One bodyweight measurement, stored in canonical metric (kilograms).
/// The Lifestyle tab renders the trend over the most recent 14 days
/// and exposes the deltas; everything else converts to/from imperial
/// at the UI boundary based on `bodyMetrics.unit`.
struct WeightEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let kg: Double

    init(id: UUID = UUID(), date: Date, kg: Double) {
        self.id = id
        self.date = date
        self.kg = kg
    }
}

/// One workout session logged on the Lifestyle tab. Free-form name
/// (e.g. "Push day", "Hill sprints") plus the spec'd sets/reps/duration
/// fields — intentionally lightweight so this isn't a competing gym
/// app, just enough structure to feed the daily card subtitle and a
/// future Analytics-tab workout summary.
struct WorkoutEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let name: String
    let sets: Int
    let reps: Int
    let durationMinutes: Int

    init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        sets: Int,
        reps: Int,
        durationMinutes: Int
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.sets = sets
        self.reps = reps
        self.durationMinutes = durationMinutes
    }
}

/// Per-day macro and water totals consumed. Keyed by start-of-day so a
/// dose logged at 11:55 pm and another at 12:05 am sit in different
/// daily buckets, matching the dialing the user sees on the Lifestyle
/// rings. Currently populated by the meal-scanner flow; manual logging
/// is a follow-up.
struct DailyConsumption: Codable, Hashable, Sendable {
    var date: Date
    var caloriesKcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var waterOz: Int

    static func empty(on date: Date) -> DailyConsumption {
        DailyConsumption(
            date: Calendar.current.startOfDay(for: date),
            caloriesKcal: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            waterOz: 0
        )
    }
}

struct UserProfile: Codable, Sendable {
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
    /// Set when the user opts in on the onboarding email-capture step.
    /// Local-only today; will be drained into Supabase + Resend when the
    /// backend ships.
    var emailSubscription: EmailSubscription?
    /// Bodyweight history surfaced on the Lifestyle tab's 14-day
    /// sparkline. Newest-last so the sparkline iteration order matches
    /// the visual axis without re-sorting on every render.
    var weightHistory: [WeightEntry]
    /// Filenames (relative to the app's Documents directory) of progress
    /// photos the user has captured. The actual JPEG data lives on disk —
    /// the profile carries only the references so the JSON stays compact.
    var progressPhotoFilenames: [String]
    /// Per-day consumption totals keyed by ISO yyyy-MM-dd start-of-day
    /// strings. Stored as a dictionary so the meal-scanner roll-up can
    /// upsert today's bucket without scanning the array.
    var dailyConsumption: [String: DailyConsumption]
    /// Workout sessions logged on the Lifestyle tab. Newest-last so
    /// callers iterating forward see chronological order without
    /// re-sorting.
    var workoutHistory: [WorkoutEntry]
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
    /// User-defined foods surfaced in the food library's "My Foods"
    /// tab. Travels on the profile so CloudKit sync carries it across
    /// the user's devices alongside everything else they care about
    /// (targets, weight history). Newest-first so the tab lands on the
    /// just-added food without re-sorting.
    var customFoods: [CustomFood]
    /// Set of food IDs the user has starred in the food library —
    /// barcodes for OFF results, `custom:<uuid>` for `customFoods`.
    /// Encoded as an array on disk because Set lacks a deterministic
    /// JSON ordering; decoded back into a Set so membership checks are
    /// O(1) in the result list.
    var favoriteFoodIDs: Set<String>
    /// Individual meal log entries — the building block for the per-
    /// category breakdown card and (eventually) HealthKit dietary-
    /// energy samples. The aggregate `dailyConsumption` still drives
    /// the macro rings; this is the per-meal sidecar. Newest-last so
    /// chronological iteration matches the visual log order.
    var mealHistory: [MealEntry]
    /// User opted in to having each logged meal mirrored as Apple
    /// Health dietary-energy / protein / carbs / fat / fiber samples.
    /// Disabled by default — we only prompt for HK write permission
    /// after the user flips this on in Profile. The corresponding HK
    /// authorization is requested at toggle-time, not at install.
    var healthKitNutritionEnabled: Bool
    /// Daily wellness check-ins. One entry per calendar day; a
    /// re-save on the same day replaces the previous entry through
    /// `LifestyleDataLogic.logOutcome`. Newest-last so chronological
    /// iteration matches visual timeline order.
    var outcomeHistory: [OutcomeEntry]
    /// Blood-work entries — the optimisation cohort's signal for
    /// "is this protocol moving real biomarkers?" Multiple entries
    /// per panel allowed (one per draw date); ordering enforced on
    /// the view side. CloudKit-synced so a user can see their full
    /// labs history on any device.
    var labHistory: [LabValue]
    /// Identifier of the timezone the user was in on the last app
    /// launch. Compared against `TimeZone.current` on every launch
    /// so the travel-detection prompt can fire when the user has
    /// crossed into a new zone — either to offer a schedule shift
    /// to local clock, or to keep doses on the origin clock.
    /// Stored as `String` (the IANA identifier) for stable diffs;
    /// `nil` only on a fresh install before the first launch.
    var lastKnownTimezoneIdentifier: String?
    /// Calendar days the user has "frozen" their streak against —
    /// either deliberately (tapped Use freeze before a missed
    /// day) or earned from a milestone reward. Keyed by start-of-
    /// day so the streak engine can treat them as
    /// counted-as-completed. Stored as ISO yyyy-MM-dd strings
    /// because Set<Date> would need a hashing strategy that
    /// matched the engine's day key; strings are unambiguous and
    /// human-readable in the JSON dump.
    var streakFreezeDays: Set<String>
    /// Saved recipes — named combinations of one or more foods.
    /// Lets the user one-tap-log a composite meal ("breakfast
    /// bowl") that would otherwise require several separate
    /// food-library taps. Newest-first by updatedAt so the recipe
    /// list reads "what I just edited" on top.
    var recipes: [Recipe]
    /// Free-form journal entries attached to specific protocols
    /// on specific days. The qualitative companion to the
    /// quantitative dose / meal / lab data — captures "felt
    /// great after BPC today" or "side-effect: mild headache"
    /// without the user reaching for a separate notes app.
    var protocolNotes: [ProtocolNote]
    /// User-controlled opt-out for the AI weekly summary feature
    /// (Pro-only, defaults to on). Surfaces as a toggle on the
    /// Profile → Settings row. Set to `false` to suppress both
    /// the Sunday notification and the on-device Today card.
    var weeklySummaryEnabled: Bool
    /// Cached weekly summaries keyed by ISO week-start ("yyyy-MM-dd"
    /// of the Monday). One entry per generated week — capped on
    /// write to the most-recent 26 weeks so the JSON stays small
    /// (~13 KB at full cap).
    var weeklySummaries: [String: WeeklySummary]

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
        emailSubscription: EmailSubscription? = nil,
        weightHistory: [WeightEntry] = [],
        progressPhotoFilenames: [String] = [],
        dailyConsumption: [String: DailyConsumption] = [:],
        workoutHistory: [WorkoutEntry] = [],
        avatarImageData: Data? = nil,
        bio: String = "",
        primaryGoal: String? = nil,
        customFoods: [CustomFood] = [],
        favoriteFoodIDs: Set<String> = [],
        mealHistory: [MealEntry] = [],
        healthKitNutritionEnabled: Bool = false,
        outcomeHistory: [OutcomeEntry] = [],
        labHistory: [LabValue] = [],
        lastKnownTimezoneIdentifier: String? = nil,
        streakFreezeDays: Set<String> = [],
        recipes: [Recipe] = [],
        protocolNotes: [ProtocolNote] = [],
        weeklySummaryEnabled: Bool = true,
        weeklySummaries: [String: WeeklySummary] = [:]
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
        self.emailSubscription = emailSubscription
        self.weightHistory = weightHistory
        self.progressPhotoFilenames = progressPhotoFilenames
        self.dailyConsumption = dailyConsumption
        self.workoutHistory = workoutHistory
        self.avatarImageData = avatarImageData
        self.bio = bio
        self.primaryGoal = primaryGoal
        self.customFoods = customFoods
        self.favoriteFoodIDs = favoriteFoodIDs
        self.mealHistory = mealHistory
        self.healthKitNutritionEnabled = healthKitNutritionEnabled
        self.outcomeHistory = outcomeHistory
        self.labHistory = labHistory
        self.lastKnownTimezoneIdentifier = lastKnownTimezoneIdentifier
        self.streakFreezeDays = streakFreezeDays
        self.recipes = recipes
        self.protocolNotes = protocolNotes
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.weeklySummaries = weeklySummaries
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
        emailSubscription = try container.decodeIfPresent(EmailSubscription.self, forKey: .emailSubscription)
        weightHistory = try container.decodeIfPresent([WeightEntry].self, forKey: .weightHistory) ?? []
        progressPhotoFilenames = try container.decodeIfPresent([String].self, forKey: .progressPhotoFilenames) ?? []
        dailyConsumption = try container.decodeIfPresent([String: DailyConsumption].self, forKey: .dailyConsumption) ?? [:]
        workoutHistory = try container.decodeIfPresent([WorkoutEntry].self, forKey: .workoutHistory) ?? []
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        bio = try container.decodeIfPresent(String.self, forKey: .bio) ?? ""
        primaryGoal = try container.decodeIfPresent(String.self, forKey: .primaryGoal)
        customFoods = try container.decodeIfPresent([CustomFood].self, forKey: .customFoods) ?? []
        favoriteFoodIDs = Set(
            try container.decodeIfPresent([String].self, forKey: .favoriteFoodIDs) ?? []
        )
        mealHistory = try container.decodeIfPresent([MealEntry].self, forKey: .mealHistory) ?? []
        healthKitNutritionEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthKitNutritionEnabled) ?? false
        outcomeHistory = try container.decodeIfPresent([OutcomeEntry].self, forKey: .outcomeHistory) ?? []
        labHistory = try container.decodeIfPresent([LabValue].self, forKey: .labHistory) ?? []
        lastKnownTimezoneIdentifier = try container.decodeIfPresent(String.self, forKey: .lastKnownTimezoneIdentifier)
        streakFreezeDays = Set(
            try container.decodeIfPresent([String].self, forKey: .streakFreezeDays) ?? []
        )
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        protocolNotes = try container.decodeIfPresent([ProtocolNote].self, forKey: .protocolNotes) ?? []
        weeklySummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklySummaryEnabled) ?? true
        weeklySummaries = try container.decodeIfPresent([String: WeeklySummary].self, forKey: .weeklySummaries) ?? [:]
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
