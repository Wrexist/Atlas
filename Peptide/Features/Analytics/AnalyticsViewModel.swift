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

    var totalDoses: Int {
        MockEntries.allEntries.filter(\.completed).count
    }

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        for dayOffset in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dayEntries = MockEntries.allEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }
            guard !dayEntries.isEmpty else { continue }
            if dayEntries.allSatisfy(\.completed) { streak += 1 } else { break }
        }
        return streak
    }

    var bestStreak: Int {
        max(currentStreak, 18)
    }

    var complianceTrend: Double {
        guard complianceData.count >= 2 else { return 0 }
        let mid = complianceData.count / 2
        let firstHalf = complianceData[..<mid].map(\.compliance).reduce(0, +) / Double(mid)
        let secondHalf = complianceData[mid...].map(\.compliance).reduce(0, +) / Double(complianceData.count - mid)
        return secondHalf - firstHalf
    }

    init() {
        regenerateData()
    }

    private func regenerateData() {
        complianceData = MockEntries.complianceData(days: selectedRange.days)
        weeklyDoseData = MockEntries.weeklyDoseData()
    }
}
