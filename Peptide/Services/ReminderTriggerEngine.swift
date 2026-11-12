import Foundation

/// Turns a reminder's weekly slots into notification triggers that keep
/// firing whether or not Atlas is opened again.
///
/// Repeating calendar triggers carry a reminder indefinitely, where a
/// rolling window of one-shots went silent a few days after the last
/// launch. A repeat cannot skip a single day, so a slot whose next
/// occurrence is already done becomes a one-shot a week later instead;
/// the next re-plan after that occurrence restores the repeat.
enum ReminderTriggerEngine {
    /// Every slot's next occurrence falls within this many days.
    static let horizonDays = 7

    /// A weekly time slot. `weekday` is a `Calendar` weekday, 1 = Sunday.
    struct Slot: Hashable, Sendable {
        let weekday: Int
        let hour: Int
        let minute: Int
    }

    struct Trigger: Equatable, Sendable {
        /// Stable per slot, so it can end a request identifier: "everyday"
        /// for one every-day repeat, otherwise "w" plus the weekday.
        let key: String
        let components: DateComponents
        let repeats: Bool
        let nextFireDate: Date
    }

    /// One every-day repeat when all seven weekdays share a time and
    /// nothing is skipped, which keeps a daily reminder to one of iOS's
    /// 64 pending slots; otherwise one trigger per weekday. Soonest first.
    ///
    /// - Parameter isSkipped: whether the occurrence at the given date is
    ///   already done. Only asked about each slot's next occurrence.
    static func triggers(
        for slots: [Slot],
        now: Date,
        calendar: Calendar,
        isSkipped: (Date) -> Bool
    ) -> [Trigger] {
        let upcoming = Set(slots).compactMap { slot -> (slot: Slot, next: Date, skipped: Bool)? in
            guard let next = calendar.nextDate(after: now, matching: weekly(slot), matchingPolicy: .nextTime) else { return nil }
            return (slot, next, isSkipped(next))
        }
        let times = Set(upcoming.map { $0.slot.hour * 60 + $0.slot.minute })
        let coversEveryDay = Set(upcoming.map { $0.slot.weekday }) == Set(1...7) && times.count == 1
        if coversEveryDay, !upcoming.contains(where: { $0.skipped }), let first = upcoming.min(by: { $0.next < $1.next }) {
            return [Trigger(
                key: "everyday",
                components: DateComponents(hour: first.slot.hour, minute: first.slot.minute),
                repeats: true,
                nextFireDate: first.next
            )]
        }
        return upcoming
            .compactMap { trigger(for: $0.slot, next: $0.next, skipped: $0.skipped, calendar: calendar) }
            .sorted { $0.nextFireDate < $1.nextFireDate }
    }

    private static func trigger(for slot: Slot, next: Date, skipped: Bool, calendar: Calendar) -> Trigger? {
        let key = "w\(slot.weekday)"
        guard skipped else {
            return Trigger(key: key, components: weekly(slot), repeats: true, nextFireDate: next)
        }
        guard let following = calendar.date(byAdding: .day, value: 7, to: next),
              let fireDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: following)
        else { return nil }
        return Trigger(
            key: key,
            components: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false,
            nextFireDate: fireDate
        )
    }

    private static func weekly(_ slot: Slot) -> DateComponents {
        DateComponents(hour: slot.hour, minute: slot.minute, weekday: slot.weekday)
    }
}
