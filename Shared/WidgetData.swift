import Foundation

enum AppGroup {
    static let identifier = "group.com.peptidesai.app"
}

struct WidgetData: Codable {
    let nextPeptideName: String
    let nextDose: String
    let nextDoseTime: Date?
    let completedToday: Int
    let totalToday: Int
    let lastUpdated: Date

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
}
