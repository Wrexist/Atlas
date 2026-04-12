import Foundation

struct InsightEngine {
    struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let type: InsightType
    }

    enum InsightType {
        case positive
        case warning
        case neutral
    }

    static func generateInsights(from entries: [ProtocolEntry], protocols: [PeptideProtocol]) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current

        // Streak insights
        let currentStreak = calculateStreak(entries: entries)
        if currentStreak >= 30 {
            insights.append(Insight(icon: "flame.fill", title: "Incredible consistency!", description: "You're on a \(currentStreak)-day streak. Top-tier dedication.", type: .positive))
        } else if currentStreak >= 7 {
            insights.append(Insight(icon: "flame.fill", title: "Strong streak!", description: "\(currentStreak) days in a row. Keep the momentum going.", type: .positive))
        }

        // Day-of-week analysis
        let dayMissPatterns = analyzeDayPatterns(entries: entries)
        if let worstDay = dayMissPatterns.max(by: { $0.value < $1.value }), worstDay.value > 0.3 {
            let dayNames = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let dayName = dayNames[worstDay.key]
            insights.append(Insight(icon: "calendar.badge.exclamationmark", title: "Pattern detected", description: "You tend to miss doses on \(dayName)s. Consider setting an extra reminder.", type: .warning))
        }

        // Time-of-day analysis
        let eveningEntries = entries.filter {
            let hour = calendar.component(.hour, from: $0.date)
            return hour >= 18
        }
        let eveningMissRate = eveningEntries.isEmpty ? 0 : Double(eveningEntries.filter { !$0.completed }.count) / Double(eveningEntries.count)
        if eveningMissRate > 0.3 && eveningEntries.count > 5 {
            insights.append(Insight(icon: "moon.fill", title: "Evening doses need attention", description: "You miss \(Int(eveningMissRate * 100))% of evening doses. Try linking them to a routine.", type: .warning))
        }

        // Compliance trend
        let recentCompliance = complianceForRange(entries: entries, days: 7)
        let olderCompliance = complianceForRange(entries: entries, days: 30)
        if recentCompliance > olderCompliance + 0.1 {
            insights.append(Insight(icon: "arrow.up.right", title: "Compliance improving", description: "Your 7-day compliance is \(Int(recentCompliance * 100))%, up from \(Int(olderCompliance * 100))% monthly average.", type: .positive))
        } else if recentCompliance < olderCompliance - 0.15 {
            insights.append(Insight(icon: "arrow.down.right", title: "Compliance dipping", description: "Recent compliance dropped to \(Int(recentCompliance * 100))%. Your average is \(Int(olderCompliance * 100))%.", type: .warning))
        }

        // Protocol count
        let activeCount = protocols.filter { $0.status == .active }.count
        if activeCount >= 3 {
            insights.append(Insight(icon: "exclamationmark.triangle", title: "Many active protocols", description: "Running \(activeCount) protocols. Consider focusing on fewer for better compliance.", type: .neutral))
        }

        // Total doses milestone
        let totalCompleted = entries.filter(\.completed).count
        let milestones = [50, 100, 250, 500, 1000]
        for milestone in milestones {
            if totalCompleted >= milestone && totalCompleted < milestone + 10 {
                insights.append(Insight(icon: "star.fill", title: "Milestone reached!", description: "You've logged over \(milestone) doses. Outstanding commitment.", type: .positive))
                break
            }
        }

        return insights
    }

    private static func calculateStreak(entries: [ProtocolEntry]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        for dayOffset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
            if dayEntries.isEmpty { continue }
            if !dayEntries.contains(where: \.completed) { break }
            streak += 1
        }
        return streak
    }

    private static func analyzeDayPatterns(entries: [ProtocolEntry]) -> [Int: Double] {
        let calendar = Calendar.current
        var dayMissRates: [Int: (missed: Int, total: Int)] = [:]

        for entry in entries {
            let weekday = calendar.component(.weekday, from: entry.date)
            let isoDay = weekday == 1 ? 7 : weekday - 1
            var current = dayMissRates[isoDay, default: (0, 0)]
            current.total += 1
            if !entry.completed { current.missed += 1 }
            dayMissRates[isoDay] = current
        }

        return dayMissRates.mapValues { pair in
            pair.total > 0 ? Double(pair.missed) / Double(pair.total) : 0
        }
    }

    private static func complianceForRange(entries: [ProtocolEntry], days: Int) -> Double {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return 0 }
        let rangeEntries = entries.filter { $0.date >= cutoff }
        guard !rangeEntries.isEmpty else { return 0 }
        return Double(rangeEntries.filter(\.completed).count) / Double(rangeEntries.count)
    }
}
