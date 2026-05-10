import Foundation

struct WatchEntry: Codable, Identifiable {
    let id: UUID
    let protocolId: UUID
    let peptideName: String
    let abbreviation: String
    let dose: String
    let scheduledTime: String
    var completed: Bool
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
        totalDosesLogged: Int? = nil
    ) {
        self.todayEntries = todayEntries
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.lastUpdated = lastUpdated
        self.currentStreak = currentStreak
        self.weeklyCompliance = weeklyCompliance
        self.totalDosesLogged = totalDosesLogged
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
    }

    private enum CodingKeys: String, CodingKey {
        case todayEntries, completedToday, totalToday, lastUpdated
        case currentStreak, weeklyCompliance, totalDosesLogged
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
