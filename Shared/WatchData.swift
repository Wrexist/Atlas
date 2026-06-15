import Foundation

struct WatchEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let protocolId: UUID
    let peptideName: String
    let abbreviation: String
    let dose: String
    /// Wall-clock time the dose is scheduled for. Stored as a Date and
    /// transported over the WatchConnectivity JSON pipeline using the
    /// `.iso8601` encoding strategy on both ends, so display formatting
    /// stays a UI concern instead of leaking locale assumptions into the
    /// payload (which previously made `scheduledTime` unparseable for any
    /// non-en_US user).
    let scheduledTime: Date
    var completed: Bool
}

/// Compact nutrition snapshot for the Watch app. Mirrors the
/// macro-ring data shown on the iOS Meals tab so the Watch
/// surface can render a coherent "where am I against my target
/// today" glance without depending on shared types from the
/// iOS-only target. Optional throughout so the Watch app can
/// hide nutrition gracefully on installs where the user hasn't
/// logged anything yet.
struct WatchNutritionSnapshot: Codable, Hashable, Sendable {
    let caloriesToday: Int
    let calorieTarget: Int
    let proteinToday: Int
    let proteinTarget: Int
    let mealLoggingStreak: Int
    /// Number of meal entries logged today — drives the
    /// "3 meals logged" subtitle on the Watch view.
    let mealEntriesToday: Int

    var calorieProgress: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(1.0, Double(caloriesToday) / Double(calorieTarget))
    }

    var proteinProgress: Double {
        guard proteinTarget > 0 else { return 0 }
        return min(1.0, Double(proteinToday) / Double(proteinTarget))
    }
}

struct WatchData: Codable, Sendable {
    let todayEntries: [WatchEntry]
    let completedToday: Int
    let totalToday: Int
    let lastUpdated: Date
    /// Current dose-logging streak. Decode-if-present so a phone running an
    /// older build that doesn't write this field still decodes cleanly on
    /// the watch — the watch app should render "—" rather than fail.
    let currentStreak: Int?
    /// 7-day compliance as a 0…1 fraction. Same back-compat policy.
    let weeklyCompliance: Double?
    /// Total completed doses ever. Surfaced on the Watch Stats view.
    let totalDosesLogged: Int?
    /// Today's nutrition snapshot. Optional so an older build that
    /// doesn't write this field still decodes on the watch — the
    /// nutrition surface hides itself gracefully when absent.
    let nutrition: WatchNutritionSnapshot?
    /// Atlas Score (cumulative momentum) + level/tier/progress for the
    /// Watch complications. Decode-if-present like the fields above so an
    /// older phone build that doesn't write them still decodes on the watch.
    let atlasScore: Int?
    let atlasLevel: Int?
    /// Tier rawValue — bronze/silver/gold/platinum/diamond — mapped to a
    /// tint widget-side (which can't see the app's MomentumEngine).
    let atlasTier: String?
    /// 0…1 progress toward the next level.
    let atlasProgress: Double?
    /// Points banked today (drives the "+N today" affordance).
    let atlasTodayEarned: Int?
    /// Today's habit completion split by domain — health (green) and
    /// training/fitness (blue) — powering the color-coded complications.
    let healthHabitsDone: Int?
    let healthHabitsTotal: Int?
    let trainingHabitsDone: Int?
    let trainingHabitsTotal: Int?

    var compliance: Double {
        totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
    }

    init(
        todayEntries: [WatchEntry],
        completedToday: Int,
        totalToday: Int,
        lastUpdated: Date,
        currentStreak: Int? = nil,
        weeklyCompliance: Double? = nil,
        totalDosesLogged: Int? = nil,
        nutrition: WatchNutritionSnapshot? = nil,
        atlasScore: Int? = nil,
        atlasLevel: Int? = nil,
        atlasTier: String? = nil,
        atlasProgress: Double? = nil,
        atlasTodayEarned: Int? = nil,
        healthHabitsDone: Int? = nil,
        healthHabitsTotal: Int? = nil,
        trainingHabitsDone: Int? = nil,
        trainingHabitsTotal: Int? = nil
    ) {
        self.todayEntries = todayEntries
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.lastUpdated = lastUpdated
        self.currentStreak = currentStreak
        self.weeklyCompliance = weeklyCompliance
        self.totalDosesLogged = totalDosesLogged
        self.nutrition = nutrition
        self.atlasScore = atlasScore
        self.atlasLevel = atlasLevel
        self.atlasTier = atlasTier
        self.atlasProgress = atlasProgress
        self.atlasTodayEarned = atlasTodayEarned
        self.healthHabitsDone = healthHabitsDone
        self.healthHabitsTotal = healthHabitsTotal
        self.trainingHabitsDone = trainingHabitsDone
        self.trainingHabitsTotal = trainingHabitsTotal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayEntries = try c.decode([WatchEntry].self, forKey: .todayEntries)
        completedToday = try c.decode(Int.self, forKey: .completedToday)
        totalToday = try c.decode(Int.self, forKey: .totalToday)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak)
        weeklyCompliance = try c.decodeIfPresent(Double.self, forKey: .weeklyCompliance)
        totalDosesLogged = try c.decodeIfPresent(Int.self, forKey: .totalDosesLogged)
        nutrition = try c.decodeIfPresent(WatchNutritionSnapshot.self, forKey: .nutrition)
        atlasScore = try c.decodeIfPresent(Int.self, forKey: .atlasScore)
        atlasLevel = try c.decodeIfPresent(Int.self, forKey: .atlasLevel)
        atlasTier = try c.decodeIfPresent(String.self, forKey: .atlasTier)
        atlasProgress = try c.decodeIfPresent(Double.self, forKey: .atlasProgress)
        atlasTodayEarned = try c.decodeIfPresent(Int.self, forKey: .atlasTodayEarned)
        healthHabitsDone = try c.decodeIfPresent(Int.self, forKey: .healthHabitsDone)
        healthHabitsTotal = try c.decodeIfPresent(Int.self, forKey: .healthHabitsTotal)
        trainingHabitsDone = try c.decodeIfPresent(Int.self, forKey: .trainingHabitsDone)
        trainingHabitsTotal = try c.decodeIfPresent(Int.self, forKey: .trainingHabitsTotal)
    }

    private enum CodingKeys: String, CodingKey {
        case todayEntries, completedToday, totalToday, lastUpdated
        case currentStreak, weeklyCompliance, totalDosesLogged
        case nutrition
        case atlasScore, atlasLevel, atlasTier, atlasProgress, atlasTodayEarned
        case healthHabitsDone, healthHabitsTotal
        case trainingHabitsDone, trainingHabitsTotal
    }

    static let empty = WatchData(
        todayEntries: [],
        completedToday: 0,
        totalToday: 0,
        lastUpdated: .distantPast
    )
}

enum WatchMessage {
    static let markComplete = "markComplete"
    static let markIncomplete = "markIncomplete"
    static let entryIdKey = "entryId"
    static let protocolIdKey = "protocolId"
    /// Watch → phone "log water" command. Carries `ozKey` with an
    /// integer ounces amount. The phone applies the log through
    /// the same `dataStore.logWater` path used by the in-app
    /// quick-add chips, so widget reload + Watch sync + HK write
    /// all fire for free.
    static let logWater = "logWater"
    static let ozKey = "oz"
}
