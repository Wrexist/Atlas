import Foundation

/// One-time reset of `UserProfile.weeklySummaryEnabled` to off.
///
/// The weekly recap sends HRV and other health aggregates to Anthropic,
/// so its default flipped from on to off — but profiles saved while the
/// default was on persisted `true` without the user ever choosing it.
/// This turns those off once, on the first profile load after upgrade;
/// the user can opt back in from Profile → Settings. A device with no
/// stored profile (a new install) is only marked done, so a later
/// opt-in there is never undone.
enum WeeklySummaryOptInMigration {
    static let defaultsKey = "weeklySummaryOptInMigrationV1"

    /// Runs once per `defaults`. Returns true when it changed `profile`,
    /// so the caller knows to persist it.
    static func apply(to profile: inout UserProfile, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: defaultsKey) else { return false }
        markCompleted(in: defaults)
        guard profile.weeklySummaryEnabled else { return false }
        profile.weeklySummaryEnabled = false
        return true
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }
}
