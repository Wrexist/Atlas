import SwiftUI

@Observable
final class HomeViewModel {
    var profile = MockProfile.current
    var activeProtocols = MockProtocols.activeProtocols
    var todayEntries = MockEntries.todayEntries()

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    var dateString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var protocolScore: Double {
        let completed = todayEntries.filter(\.completed).count
        let total = todayEntries.count
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var completedCount: Int {
        todayEntries.filter(\.completed).count
    }

    var totalCount: Int {
        todayEntries.count
    }

    var nextDose: ProtocolEntry? {
        let now = Date()
        return todayEntries
            .filter { !$0.completed && $0.date > now }
            .min(by: { $0.date < $1.date })
    }

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        for dayOffset in 0..<60 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dayEntries = MockEntries.allEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }
            guard !dayEntries.isEmpty else { continue }
            let allDone = dayEntries.allSatisfy(\.completed)
            if allDone { streak += 1 } else { break }
        }
        return streak
    }

    var totalDaysLogged: Int {
        let calendar = Calendar.current
        let uniqueDays = Set(MockEntries.allEntries.filter(\.completed).map {
            calendar.startOfDay(for: $0.date)
        })
        return uniqueDays.count
    }

    func toggleEntry(_ entry: ProtocolEntry) {
        if let index = todayEntries.firstIndex(where: { $0.id == entry.id }) {
            todayEntries[index].completed.toggle()
        }
    }
}
