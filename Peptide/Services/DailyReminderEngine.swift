import Foundation

/// Plans the next few days of daily reminders as one-shot requests.
///
/// One-shots rather than repeating calendar triggers so a reminder can be
/// dropped for a single day: log lunch at 12:10 and the 12:30 lunch nudge
/// for today disappears, tomorrow's stays. The plan is rebuilt every time
/// the app comes to the foreground or leaves it, so the window keeps
/// rolling forward for anyone who opens Atlas at least every few days —
/// and quietly stops nagging someone who has stopped.
enum DailyReminderEngine {
    /// Days covered by one plan, today included. Five kinds × 3 days keeps
    /// the worst case at 15 of iOS's 64 pending slots, leaving dose and
    /// habit reminders their share.
    static let lookaheadDays = 3

    struct Planned: Equatable, Sendable {
        let kind: DailyReminderKind
        let fireDate: Date
        let id: String
    }

    /// - Parameters:
    ///   - trainingWeekdays: `Calendar` weekday values (1 = Sunday) the
    ///     workout reminder fires on. Empty means every day — someone
    ///     who skipped picking days in onboarding still gets the nudge.
    ///   - isDone: whether `kind` is already logged on the day containing
    ///     the date. Only consulted for reminders still in the future.
    static func plan(
        settings: DailyReminderSettings,
        trainingWeekdays: Set<Int>,
        now: Date,
        calendar: Calendar = .current,
        isDone: (DailyReminderKind, Date) -> Bool
    ) -> [Planned] {
        let today = calendar.startOfDay(for: now)
        var planned: [Planned] = []

        for offset in 0..<lookaheadDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)

            for kind in DailyReminderKind.allCases {
                let slot = settings.slot(kind)
                guard slot.isEnabled,
                      let fireDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day),
                      fireDate > now
                else { continue }
                if kind == .workout, !trainingWeekdays.isEmpty, !trainingWeekdays.contains(weekday) { continue }
                if isDone(kind, day) { continue }
                planned.append(Planned(kind: kind, fireDate: fireDate, id: identifier(kind: kind, day: day, calendar: calendar)))
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    static func identifier(kind: DailyReminderKind, day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "\(NotificationService.dailyIDPrefix)\(kind.rawValue)-\(stamp)"
    }

    /// Entries from the day before `day` in the given meal slot — what the
    /// "Same as yesterday" action re-logs. Empty when there is nothing to
    /// repeat, in which case the reminder offers only the scanner.
    static func previousDayMeals(
        _ category: MealCategory,
        before day: Date,
        in history: [MealEntry],
        calendar: Calendar = .current
    ) -> [MealEntry] {
        guard let previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day)) else { return [] }
        return history
            .filter { $0.category == category && calendar.isDate($0.date, inSameDayAs: previous) }
            .sorted { $0.date < $1.date }
    }

    /// Parses the weight typed into the notification's reply field. Takes
    /// "82,4", "82.4 kg" or "181 lb" alike; the unit suffix is ignored in
    /// favour of the user's display unit. Out-of-range values return nil
    /// so a slip of the thumb ("8.24") never lands in the weight history.
    static func parsedWeightKilograms(_ text: String, unit: MeasurementUnit) -> Double? {
        let numeric = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(numeric) else { return nil }
        let kilograms = unit.kilograms(fromDisplayed: value)
        guard (25...350).contains(kilograms) else { return nil }
        return kilograms
    }
}
