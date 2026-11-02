import Foundation

/// The rules behind daily supplements: what counts as taken today, the
/// streak, the 7-day dots and which reminders to plan. Every day is a
/// local calendar day of the injected calendar, so "today" resets at the
/// user's midnight and tests can pin a time zone.
enum SupplementEngine {
    /// Days covered by one reminder plan, today included — the same
    /// rolling window as `DailyReminderEngine`.
    static let lookaheadDays = 3

    /// Supplement share of iOS's 64 pending requests, beside habits (32)
    /// and the daily meal / training / weigh-in nudges (15).
    static let reminderLimit = 12

    /// Length of the dot row in a supplement's settings.
    static let weekLength = 7

    struct Row: Identifiable, Equatable, Sendable {
        let supplement: Supplement
        let isTaken: Bool
        var id: UUID { supplement.id }
    }

    struct DayDot: Identifiable, Equatable, Sendable {
        let day: Date
        let isTaken: Bool
        let isToday: Bool
        var id: Date { day }
    }

    struct PlannedReminder: Equatable, Sendable {
        let supplement: Supplement
        let fireDate: Date
        let id: String
    }

    // MARK: - Days

    /// "2026-10-28" for the local day containing `date`.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func isTaken(_ supplement: Supplement, on date: Date, calendar: Calendar) -> Bool {
        supplement.takenDays.contains(dayKey(for: date, calendar: calendar))
    }

    /// Checks the supplement off for `date`'s day, or un-checks it when it
    /// already was. Keeps `takenDays` sorted and free of duplicates.
    static func toggled(_ supplement: Supplement, on date: Date, calendar: Calendar) -> Supplement {
        let key = dayKey(for: date, calendar: calendar)
        var days = Set(supplement.takenDays)
        if days.contains(key) {
            days.remove(key)
        } else {
            days.insert(key)
        }
        var copy = supplement
        copy.takenDays = days.sorted()
        return copy
    }

    // MARK: - Streak

    /// Consecutive days taken, ending today. A today that isn't checked
    /// off yet is still open, so it neither counts nor breaks the run.
    static func streak(_ supplement: Supplement, now: Date, calendar: Calendar) -> Int {
        let taken = Set(supplement.takenDays)
        var day = calendar.startOfDay(for: now)
        if !taken.contains(dayKey(for: day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while taken.contains(dayKey(for: day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The last `weekLength` days, oldest first, ending today.
    static func week(_ supplement: Supplement, now: Date, calendar: Calendar) -> [DayDot] {
        let today = calendar.startOfDay(for: now)
        let taken = Set(supplement.takenDays)
        return (0..<weekLength).reversed().compactMap { (offset: Int) -> DayDot? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayDot(
                day: day,
                isTaken: taken.contains(dayKey(for: day, calendar: calendar)),
                isToday: offset == 0
            )
        }
    }

    // MARK: - Today

    /// Timed supplements in clock order, then the any-time ones in the
    /// order they were added.
    static func ordered(_ supplements: [Supplement]) -> [Supplement] {
        supplements.sorted { (lhs: Supplement, rhs: Supplement) -> Bool in
            if let left = lhs.minuteOfDay, let right = rhs.minuteOfDay, left != right { return left < right }
            if (lhs.minuteOfDay == nil) != (rhs.minuteOfDay == nil) { return lhs.minuteOfDay != nil }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// The supplements that existed on `date`'s day, in `ordered` order,
    /// so a browsed past day doesn't list one added since as missed.
    static func rows(_ supplements: [Supplement], on date: Date, calendar: Calendar) -> [Row] {
        let day = calendar.startOfDay(for: date)
        return ordered(supplements)
            .filter { calendar.startOfDay(for: $0.createdAt) <= day }
            .map { Row(supplement: $0, isTaken: isTaken($0, on: date, calendar: calendar)) }
    }

    // MARK: - Reminders

    /// One-shot reminders for the next `lookaheadDays`, skipping a day the
    /// supplement is already taken and any time already past. Soonest
    /// first, capped at `limit`.
    static func reminderPlan(
        _ supplements: [Supplement],
        now: Date,
        calendar: Calendar,
        limit: Int = reminderLimit
    ) -> [PlannedReminder] {
        let today = calendar.startOfDay(for: now)
        var planned: [PlannedReminder] = []
        for supplement in supplements where supplement.reminderEnabled {
            guard let minuteOfDay = supplement.minuteOfDay else { continue }
            for offset in 0..<lookaheadDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      !isTaken(supplement, on: day, calendar: calendar),
                      let fireDate = calendar.date(
                          bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day
                      ),
                      fireDate > now
                else { continue }
                planned.append(PlannedReminder(
                    supplement: supplement,
                    fireDate: fireDate,
                    id: reminderIdentifier(supplementID: supplement.id, day: day, calendar: calendar)
                ))
            }
        }
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Lives in the daily-reminder namespace, so `DailyReminderScheduler`
    /// replaces it on every pass and the dose scheduler leaves it alone.
    static func reminderIdentifier(supplementID: UUID, day: Date, calendar: Calendar) -> String {
        let stamp = dayKey(for: day, calendar: calendar).replacingOccurrences(of: "-", with: "")
        return "\(NotificationService.dailyIDPrefix)supplement-\(supplementID.uuidString)-\(stamp)"
    }
}
