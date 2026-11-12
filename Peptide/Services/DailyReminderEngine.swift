import Foundation

/// Plans the daily reminders as repeating triggers (see
/// `ReminderTriggerEngine`), so they keep coming on days Atlas is not
/// opened. A reminder can still be dropped for a single day: log lunch
/// at 12:10 and today's 12:30 lunch nudge disappears, tomorrow's stays.
/// The plan is rebuilt every time the app comes to the foreground or
/// leaves it.
enum DailyReminderEngine {
    /// Share of iOS's 64 pending slots, beside habits (26) and
    /// supplements (12); doses get what is left. Usually one per kind; a
    /// kind already done today takes one per weekday until the next
    /// re-plan, so this fits three such kinds whole.
    static let requestLimit = 21

    struct Planned: Equatable, Sendable {
        let kind: DailyReminderKind
        let trigger: ReminderTriggerEngine.Trigger
        let id: String

        var fireDate: Date { trigger.nextFireDate }
    }

    /// - Parameters:
    ///   - trainingWeekdays: `Calendar` weekday values (1 = Sunday) the
    ///     workout reminder fires on. Empty means every day — someone
    ///     who skipped picking days in onboarding still gets the nudge.
    ///   - isDone: whether `kind` is already logged on the day containing
    ///     the date. Only consulted for reminders still in the future.
    ///   - limit: kinds are kept whole, in `DailyReminderKind.allCases`
    ///     order, while they fit (see `ReminderTriggerEngine.capped`).
    static func plan(
        settings: DailyReminderSettings,
        trainingWeekdays: Set<Int>,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = requestLimit,
        isDone: (DailyReminderKind, Date) -> Bool
    ) -> [Planned] {
        var groups: [[Planned]] = []
        for kind in DailyReminderKind.allCases {
            let slot = settings.slot(kind)
            guard slot.isEnabled else { continue }
            let weekdays = kind == .workout && !trainingWeekdays.isEmpty ? Array(trainingWeekdays) : Array(1...7)
            let slots = weekdays.map { ReminderTriggerEngine.Slot(weekday: $0, hour: slot.hour, minute: slot.minute) }
            let triggers = ReminderTriggerEngine.triggers(for: slots, now: now, calendar: calendar) { isDone(kind, $0) }
            groups.append(triggers.map { Planned(kind: kind, trigger: $0, id: identifier(kind: kind, triggerKey: $0.key)) })
        }
        return ReminderTriggerEngine.capped(groups, limit: limit)
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    static func identifier(kind: DailyReminderKind, triggerKey: String) -> String {
        "\(NotificationService.dailyIDPrefix)\(kind.rawValue)-\(triggerKey)"
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

    static let plausibleWeightKilograms: ClosedRange<Double> = 25...350

    /// Parses the weight typed into the notification's reply field. Takes
    /// "82,4", "82.4 kg", "181 lb" or a dictated "82.4." alike. A typed
    /// unit wins over the user's display unit, so "181 lb" from a metric
    /// user is 82 kg, not 181. Out-of-range values return nil so a slip of
    /// the thumb ("8.24") never lands in the weight history.
    static func parsedWeightKilograms(_ text: String, unit: MeasurementUnit) -> Double? {
        var numeric = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        while numeric.hasSuffix(".") { numeric.removeLast() }
        guard let value = Double(numeric) else { return nil }
        let kilograms = (typedUnit(in: text) ?? unit).kilograms(fromDisplayed: value)
        guard plausibleWeightKilograms.contains(kilograms) else { return nil }
        return kilograms
    }

    /// The unit written after the number, if any: kg / kilo, or lb / lbs /
    /// pound, plus the Swedish "pund".
    private static func typedUnit(in text: String) -> MeasurementUnit? {
        let lowered = text.lowercased()
        if lowered.contains("kg") || lowered.contains("kilo") { return .metric }
        if lowered.contains("lb") || lowered.contains("pound") || lowered.contains("pund") { return .imperial }
        return nil
    }
}
