import Foundation

struct ProtocolSchedule: Hashable {
    let daysOfWeek: [Int]  // 1=Mon, 7=Sun
    let timesPerDay: Int
    let preferredTimes: [String]

    var daysDescription: String {
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        if daysOfWeek.count == 7 { return "Every day" }
        return daysOfWeek.map { dayNames[$0 - 1] }.joined(separator: ", ")
    }
}

struct PeptideProtocol: Identifiable, Hashable {
    let id: UUID
    let name: String
    let peptides: [Peptide]
    let schedule: ProtocolSchedule
    let cycleLengthWeeks: Int
    let startDate: Date
    let status: ProtocolStatus
    let notes: String

    var endDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: cycleLengthWeeks, to: startDate) ?? startDate
    }

    var cycleProgress: Double {
        let total = endDate.timeIntervalSince(startDate)
        let elapsed = Date().timeIntervalSince(startDate)
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }

    var daysRemaining: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(days, 0)
    }

    var weekNumber: Int {
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: startDate, to: Date()).weekOfYear ?? 0
        return min(weeks + 1, cycleLengthWeeks)
    }

    static func == (lhs: PeptideProtocol, rhs: PeptideProtocol) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
