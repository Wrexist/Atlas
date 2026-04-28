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

    var compliance: Double {
        totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
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
