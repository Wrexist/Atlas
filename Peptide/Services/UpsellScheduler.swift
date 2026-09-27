import Foundation

/// Decides when a user who declined the onboarding trial sees the offer
/// one more time. The re-offer waits until the user has actually used the
/// app — at least `minActiveDays` distinct days, and `minDaysSinceDecline`
/// calendar days after saying no — and then shows once, ever.
///
/// Inputs are engagement and entitlement only. Health readings never
/// feed this decision.
enum UpsellScheduler {
    static let minActiveDays = 3
    static let minDaysSinceDecline = 3
    /// Only "at least N days" matters, so the stored list is capped to
    /// keep the defaults entry small.
    static let maxStoredActiveDays = 30

    private static let declinedAtKey = "upsell.trialDeclinedAt"
    private static let activeDaysKey = "upsell.activeDays"
    private static let winBackShownKey = "upsell.winBackShown"

    // MARK: - Pure rules

    static func shouldShowWinBack(
        declinedAt: Date?,
        activeDayCount: Int,
        alreadyShown: Bool,
        isPro: Bool,
        isTrialEligible: Bool,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let declinedAt, !alreadyShown, !isPro, isTrialEligible else { return false }
        guard activeDayCount >= minActiveDays else { return false }
        let start = calendar.startOfDay(for: declinedAt)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return days >= minDaysSinceDecline
    }

    /// Local calendar day as `yyyy-MM-dd`, the unit "active days" counts.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Appends `day` unless already present, keeping the newest
    /// `maxStoredActiveDays` entries.
    static func addingActiveDay(_ day: String, to days: [String]) -> [String] {
        guard !days.contains(day) else { return days }
        return Array((days + [day]).suffix(maxStoredActiveDays))
    }

    // MARK: - Persistence

    static func recordTrialDeclined(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: declinedAtKey)
    }

    static func recordActiveDay(
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        let days = defaults.stringArray(forKey: activeDaysKey) ?? []
        let updated = addingActiveDay(dayKey(for: now, calendar: calendar), to: days)
        if updated != days {
            defaults.set(updated, forKey: activeDaysKey)
        }
    }

    static func markWinBackShown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: winBackShownKey)
    }

    static func isWinBackDue(
        isPro: Bool,
        isTrialEligible: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        shouldShowWinBack(
            declinedAt: defaults.object(forKey: declinedAtKey) as? Date,
            activeDayCount: defaults.stringArray(forKey: activeDaysKey)?.count ?? 0,
            alreadyShown: defaults.bool(forKey: winBackShownKey),
            isPro: isPro,
            isTrialEligible: isTrialEligible,
            now: now,
            calendar: calendar
        )
    }
}
