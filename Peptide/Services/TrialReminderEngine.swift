import Foundation

/// Pure date math and copy for the "your trial ends in 2 days" reminder.
/// `StoreService` feeds it the trial transaction's `expirationDate` and
/// `NotificationService` owns the actual scheduling, so everything that
/// decides *whether* and *when* the reminder fires is testable here without
/// StoreKit or `UNUserNotificationCenter`.
enum TrialReminderEngine {
    /// How far ahead of the first charge the reminder fires. Matches the
    /// "ends in 2 days" copy — change both together.
    static let leadDays = 2

    /// When the reminder should fire, or `nil` when the trial ends less than
    /// `leadDays` from `now` — a reminder that fires late would claim two
    /// days of runway the user no longer has.
    static func fireDate(trialEnd: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard let fire = calendar.date(byAdding: .day, value: -leadDays, to: trialEnd),
              fire > now
        else { return nil }
        return fire
    }

    /// Notification body. `price` is the product's localised `displayPrice`,
    /// so the currency is always the user's own storefront.
    static func body(price: String, chargeDate: Date, locale: Locale = .current) -> String {
        let date = chargeDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
        return "Your Atlas Pro trial ends in 2 days — you'll be charged \(price) on \(date) unless you cancel in Settings."
    }
}
