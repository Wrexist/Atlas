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

    var currentStreak: Int { 12 }
    var totalDaysLogged: Int { 45 }

    func toggleEntry(_ entry: ProtocolEntry) {
        if let index = todayEntries.firstIndex(where: { $0.id == entry.id }) {
            todayEntries[index].completed.toggle()
        }
    }
}
