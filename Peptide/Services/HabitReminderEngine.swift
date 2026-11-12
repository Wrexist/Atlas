import Foundation

/// Plans habit reminders as repeating triggers (see
/// `ReminderTriggerEngine`), so they keep coming on days Atlas is not
/// opened. A habit ticked off before its reminder silences that day
/// only: meditate at 07:00 and today's 20:00 "Meditate" nudge is
/// dropped, tomorrow's stays. Re-planned on every foreground, background
/// and habit change.
enum HabitReminderEngine {
    struct Planned: Equatable, Sendable {
        let habit: Habit
        let trigger: ReminderTriggerEngine.Trigger
        let id: String

        var fireDate: Date { trigger.nextFireDate }
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
        let week = (0..<ReminderTriggerEngine.horizonDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
        var planned: [Planned] = []

        for habit in habits where !habit.archived {
            guard let reminderTime = habit.reminderTime else { continue }
            let hour = calendar.component(.hour, from: reminderTime)
            let minute = calendar.component(.minute, from: reminderTime)

            let slots = week
                .filter { habit.schedule.isDue(on: $0, calendar: calendar) }
                .map { day in
                    let weekday = calendar.component(.weekday, from: day)
                    let resolved = NotificationService.resolvedHabitFireTime(
                        hour: hour, minute: minute, weekday: weekday, avoiding: occupied
                    )
                    return ReminderTriggerEngine.Slot(weekday: weekday, hour: resolved.hour, minute: resolved.minute)
                }
            let triggers = ReminderTriggerEngine.triggers(for: slots, now: now, calendar: calendar) {
                isDone(habit, on: $0, entries: entries, calendar: calendar)
            }
            planned += triggers.map {
                Planned(habit: habit, trigger: $0, id: identifier(habitID: habit.id, triggerKey: $0.key))
            }
        }
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    static func identifier(habitID: UUID, triggerKey: String) -> String {
        "\(NotificationService.habitIDPrefix)\(habitID.uuidString)-\(triggerKey)"
    }

    /// Done that day, or — for a times-per-week habit — done often
    /// enough that week already, so the rest of the week stays quiet and
    /// the next week starts nudging again.
    private static func isDone(_ habit: Habit, on day: Date, entries: [HabitEntry], calendar: Calendar) -> Bool {
        let target = habit.targetValue ?? 1
        let own = entries.filter { $0.habitId == habit.id }
        if own.contains(where: { $0.value >= target && calendar.isDate($0.date, inSameDayAs: day) }) {
            return true
        }
        guard let weekly = HabitsService.weeklyProgress(for: habit, entries: own, on: day, calendar: calendar) else {
            return false
        }
        return weekly.target > 0 && weekly.count >= weekly.target
    }
}
