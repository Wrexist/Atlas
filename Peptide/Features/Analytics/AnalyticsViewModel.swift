import SwiftUI

enum TimeRange: String, CaseIterable, CustomStringConvertible {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"

    var description: String { rawValue }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        }
    }
}

@Observable
final class AnalyticsViewModel {
    var selectedRange: TimeRange = .month

    var complianceData: [(date: Date, compliance: Double)] {
        MockEntries.complianceData(days: selectedRange.days)
    }

    var weeklyDoseData: [(day: String, count: Int)] {
        MockEntries.weeklyDoseData()
    }

    var averageCompliance: Double {
        let data = complianceData
        guard !data.isEmpty else { return 0 }
        return data.map(\.compliance).reduce(0, +) / Double(data.count)
    }

    var totalDoses: Int { 127 }
    var currentStreak: Int { 12 }
    var bestStreak: Int { 18 }
    var complianceTrend: Double { 0.12 }
}
