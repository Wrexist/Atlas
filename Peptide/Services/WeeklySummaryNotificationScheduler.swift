import Foundation
import UserNotifications

/// Schedules the Sunday-morning push that surfaces a freshly
/// generated weekly summary. Repeats weekly; canceled and rescheduled
/// on every transition to `.active` so an opt-out toggle takes effect
/// immediately and so the trigger survives an app reinstall.
///
/// One notification, identifier `peptidex.weeklySummary.sunday`, so a
/// re-schedule is idempotent: remove + add against the same id and
/// the second add wins.
///
/// Tap → opens `peptidex://weekly/current` (handled in `PeptideApp`),
/// which routes to Today and presents the detail view backed by the
/// most recent cached summary.
@MainActor
enum WeeklySummaryNotificationScheduler {

    /// Identifier the schedule/cancel pair operate on. One per app,
    /// so re-scheduling replaces the previous entry rather than
    /// stacking duplicates.
    static let identifier = "peptidex.weeklySummary.sunday"

    /// Reconciles the system's pending notification list against
    /// the user's profile preference. Call on every transition to
    /// `.active` so flipping the toggle off / on takes effect on
    /// the next foreground without waiting for the next Sunday.
    static func reconcile(profile: UserProfile, isPro: Bool) async {
        guard await isAuthorised else {
            // Without notification permission there's nothing to
            // schedule — the in-app card still works.
            return
        }
        if isPro && profile.weeklySummaryEnabled {
            await schedule()
        } else {
            cancel()
        }
    }

    /// Pulls the matching pending request and replaces it with a
    /// fresh one. Sunday 9 am local time, repeating, with a
    /// `peptidex://weekly/current` deep link in `userInfo`.
    private static func schedule() async {
        let center = UNUserNotificationCenter.current()

        // Remove first so the second `.add` truly replaces. Without
        // this, a schedule call right after a manual cancel can
        // race and leave both requests pending on cold boot.
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your week in PeptideX")
        content.body = String(localized: "Tap to see how the week went — compliance, streak, and the patterns that mattered.")
        content.sound = .default
        content.userInfo = ["deeplink": "peptidex://weekly/current"]
        content.threadIdentifier = identifier

        var components = DateComponents()
        components.weekday = 1   // Sunday in Foundation's 1-indexed weekday (1=Sun)
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            AppLog.persistence.error(
                "Weekly summary notification add failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Clears the scheduled notification — used when the user
    /// flips the opt-out toggle, downgrades from Pro, or revokes
    /// notification permission.
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static var isAuthorised: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .ephemeral, .provisional:
                return true
            default:
                return false
            }
        }
    }
}
