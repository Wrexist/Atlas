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
    var selectedRange: TimeRange = .month {
        didSet { regenerateData() }
    }

    private(set) var complianceData: [(date: Date, compliance: Double)] = []
    private(set) var weeklyDoseData: [(day: String, count: Int)] = []

    var averageCompliance: Double {
        guard !complianceData.isEmpty else { return 0 }
        return complianceData.map(\.compliance).reduce(0, +) / Double(complianceData.count)
    }

    var totalDoses: Int { 127 }
    var currentStreak: Int { 12 }
    var bestStreak: Int { 18 }
    var complianceTrend: Double { 0.12 }

    init() {
        regenerateData()
    }

    private func regenerateData() {
        complianceData = MockEntries.complianceData(days: selectedRange.days)
        weeklyDoseData = MockEntries.weeklyDoseData()
    }
}
