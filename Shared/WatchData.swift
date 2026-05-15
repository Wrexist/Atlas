import Foundation

struct WatchEntry: Codable, Identifiable {
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
/// macro-ring data shown on the iOS Lifestyle tab so the Watch
/// surface can render a coherent "where am I against my target
/// today" glance without depending on shared types from the
/// iOS-only target. Optional throughout so the Watch app can
/// hide nutrition gracefully on installs where the user hasn't
/// logged anything yet.
struct WatchNutritionSnapshot: Codable, Hashable {
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

struct WatchData: Codable {
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
        nutrition: WatchNutritionSnapshot? = nil
    ) {
        self.todayEntries = todayEntries
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.lastUpdated = lastUpdated
        self.currentStreak = currentStreak
        self.weeklyCompliance = weeklyCompliance
        self.totalDosesLogged = totalDosesLogged
        self.nutrition = nutrition
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
    }

    private enum CodingKeys: String, CodingKey {
        case todayEntries, completedToday, totalToday, lastUpdated
        case currentStreak, weeklyCompliance, totalDosesLogged
        case nutrition
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
}
