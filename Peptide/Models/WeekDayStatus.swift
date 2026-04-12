import Foundation

enum DayCompletionStatus {
    case completed
    case partial
    case missed
    case future
    case today
    case noSchedule
}

struct WeekDayStatus: Identifiable {
    let id: Int
    let dayLabel: String
    let status: DayCompletionStatus
}
