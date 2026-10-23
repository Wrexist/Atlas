import Foundation

/// Plans the next few days of habit reminders as one-shot requests.
///
/// One-shots rather than repeating calendar triggers so a habit ticked
/// off before its reminder silences that day only: meditate at 07:00 and
/// the 20:00 "Meditate" nudge for today is dropped, tomorrow's stays. The
/// same rolling window as `DailyReminderEngine`, re-planned on every
/// foreground, background and habit change.
enum HabitReminderEngine {
    /// Days covered by one plan, today included.
    static let lookaheadDays = 3

    struct Planned: Equatable, Sendable {
        let habit: Habit
        let fireDate: Date
        let id: String
    }

    /// - Parameters:
    ///   - occupied: dose reminder slots (Calendar weekday, hour, minute) a
    ///     habit reminder steps past — see
    ///     `NotificationService.resolvedHabitFireTime`.
    ///   - limit: the habit share of iOS's pending-request budget; the
    ///     soonest reminders are kept.
    static func plan(
        habits: [Habit],
        entries: [HabitEntry],
        now: Date,
        calendar: Calendar = .current,
        occupied: [(weekday: Int, hour: Int, minute: Int)] = [],
        limit: Int = NotificationService.habitRequestLimit
    ) -> [Planned] {
        let today = calendar.startOfDay(for: now)
        var planned: [Planned] = []

        for habit in habits where !habit.archived {
            guard let reminderTime = habit.reminderTime else { continue }
            let hour = calendar.component(.hour, from: reminderTime)
            let minute = calendar.component(.minute, from: reminderTime)

            for offset in 0..<lookaheadDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      habit.schedule.isDue(on: day, calendar: calendar),
                      !isDone(habit, on: day, entries: entries, calendar: calendar)
                else { continue }
                let weekday = calendar.component(.weekday, from: day)
                let resolved = NotificationService.resolvedHabitFireTime(
                    hour: hour, minute: minute, weekday: weekday, avoiding: occupied
                )
                guard let fireDate = calendar.date(bySettingHour: resolved.hour, minute: resolved.minute, second: 0, of: day),
                      fireDate > now
                else { continue }
                planned.append(Planned(habit: habit, fireDate: fireDate, id: identifier(habitID: habit.id, day: day, calendar: calendar)))
            }
        }
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    static func identifier(habitID: UUID, day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "\(NotificationService.habitIDPrefix)\(habitID.uuidString)-\(stamp)"
    }

    private static func isDone(_ habit: Habit, on day: Date, entries: [HabitEntry], calendar: Calendar) -> Bool {
        let target = habit.targetValue ?? 1
        return entries.contains {
            $0.habitId == habit.id && $0.value >= target && calendar.isDate($0.date, inSameDayAs: day)
        }
    }
}
