import Foundation

enum AppGroup {
    static let identifier = "group.com.peptidesai.app"
}

/// One row in the Medium widget's "today" list. Three of these are
/// surfaced — enough to fill the widget without truncation under default
/// Dynamic Type, per `docs/SCREENSHOT_SEED_DATA_AND_FIXES.md` slot 7.
struct WidgetDoseSlot: Codable, Hashable {
    let peptideName: String
    let dose: String
    let time: Date
    let completed: Bool
}

struct WidgetData: Codable {
    let nextPeptideName: String
    let nextDose: String
    let nextDoseTime: Date?
    let completedToday: Int
    let totalToday: Int
    let lastUpdated: Date
    let upcoming: [WidgetDoseSlot]

    init(
        nextPeptideName: String,
        nextDose: String,
        nextDoseTime: Date?,
        completedToday: Int,
        totalToday: Int,
        lastUpdated: Date,
        upcoming: [WidgetDoseSlot] = []
    ) {
        self.nextPeptideName = nextPeptideName
        self.nextDose = nextDose
        self.nextDoseTime = nextDoseTime
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.lastUpdated = lastUpdated
        self.upcoming = upcoming
    }

    var compliance: Double {
        totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
    }

    static let empty = WidgetData(
        nextPeptideName: "",
        nextDose: "",
        nextDoseTime: nil,
        completedToday: 0,
        totalToday: 0,
        lastUpdated: .distantPast
    )

    // MARK: - Codable (backwards-compatible: `upcoming` is optional so older
    // payloads written before slot 7's redesign still decode cleanly).

    private enum CodingKeys: String, CodingKey {
        case nextPeptideName, nextDose, nextDoseTime
        case completedToday, totalToday, lastUpdated, upcoming
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextPeptideName = try c.decode(String.self, forKey: .nextPeptideName)
        nextDose = try c.decode(String.self, forKey: .nextDose)
        nextDoseTime = try c.decodeIfPresent(Date.self, forKey: .nextDoseTime)
        completedToday = try c.decode(Int.self, forKey: .completedToday)
        totalToday = try c.decode(Int.self, forKey: .totalToday)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        upcoming = try c.decodeIfPresent([WidgetDoseSlot].self, forKey: .upcoming) ?? []
    }
}
