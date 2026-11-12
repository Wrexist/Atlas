import Foundation
@testable import Peptide

extension ReminderTriggerEngine.Trigger {
    /// What iOS would deliver over the `days` calendar days starting with
    /// `now`'s day if Atlas were never opened again.
    func fireDates(after now: Date, days: Int, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard repeats else {
            let end = calendar.date(byAdding: .day, value: days, to: today) ?? today
            return nextFireDate > now && nextFireDate < end ? [nextFireDate] : []
        }
        guard let hour = components.hour, let minute = components.minute else { return [] }
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  components.weekday.map({ $0 == calendar.component(.weekday, from: day) }) ?? true,
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date > now
            else { return nil }
            return date
        }
    }
}

extension Array where Element == ReminderTriggerEngine.Trigger {
    func fireDates(after now: Date, days: Int, calendar: Calendar) -> [Date] {
        flatMap { $0.fireDates(after: now, days: days, calendar: calendar) }.sorted()
    }
}
