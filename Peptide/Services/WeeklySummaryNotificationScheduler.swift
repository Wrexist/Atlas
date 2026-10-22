import Foundation
import UserNotifications

/// Schedules the Sunday-morning push that surfaces a freshly
/// generated weekly summary. One-shot for the coming Sunday, and only
/// once that week has enough activity for a recap — a repeating
/// trigger pinged users whose week would only open "Recap
/// unavailable". Canceled and rescheduled on every transition to
/// `.active` so an opt-out toggle takes effect immediately and a week
/// that qualifies mid-way gets its push.
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
    static func reconcile(dataStore: DataStore, isPro: Bool) async {
        guard await isAuthorised else {
            // Without notification permission there's nothing to
            // schedule — the in-app card still works.
            return
        }
        let profile = dataStore.profile
        guard isPro, profile.weeklySummaryEnabled,
              let deliveryDate = nextDeliveryDate(after: Date()),
              WeeklySummaryEngine.build(
                  profile: profile,
                  protocols: dataStore.protocols,
                  entries: dataStore.entries,
                  workoutDates: dataStore.recentWorkoutDates(),
                  referenceDate: deliveryDate
              ) != nil
        else {
            cancel()
            return
        }
        await schedule(profile: profile, on: deliveryDate)
    }

    /// The next Sunday 9 am strictly after `now`. Its ISO week is the
    /// one the push recaps, since ISO weeks end on Sunday.
    static func nextDeliveryDate(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 9, minute: 0, weekday: 1),
            matchingPolicy: .nextTime
        )
    }

    /// Generic fallback body — used when there isn't yet a second
    /// generated summary to compare against, or when nothing tracked
    /// changed by a meaningful margin. Never asserts a trend it can't
    /// back with a real delta.
    static let genericBody = String(localized: "Tap to see how the week went — training, nutrition, recovery, and the patterns that mattered.")

    /// The two most recently *generated* summaries in `profile
    /// .weeklySummaries`, newest first. Deliberately not "this calendar
    /// week" — see `notificationBody(for:)`.
    private static func mostRecentSummaries(in profile: UserProfile) -> (current: WeeklySummary, previous: WeeklySummary?)? {
        let sorted = profile.weeklySummaries.values.sorted { $0.weekStart > $1.weekStart }
        guard let current = sorted.first else { return nil }
        return (current, sorted.dropFirst().first)
    }

    /// Builds the notification body from a real week-over-week delta when
    /// one exists, falling back to `genericBody` otherwise.
    ///
    /// Deliberately compares the two most recently *generated* summaries
    /// rather than "this calendar week vs last" — a `UNCalendarNotification-
    /// Trigger` bakes `content.body` in at schedule time (any app
    /// foreground during the week), not at Sunday-morning fire time, so
    /// describing a week still in progress would go stale the moment it
    /// actually finishes. Two already-final summaries are stable no matter
    /// when this runs. See `WeeklySummaryEngine.changeHeadline`.
    static func notificationBody(for profile: UserProfile) -> String {
        guard let (current, previous) = mostRecentSummaries(in: profile),
              let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        else {
            return genericBody
        }
        return String(
            localized: "\(headline) — tap for the full recap.",
            comment: "Weekly recap notification body — value is the week-over-week headline."
        )
    }

    /// Pulls the matching pending request and replaces it with a
    /// fresh one-shot at `date`, with a `peptidex://weekly/current`
    /// deep link in `userInfo`.
    private static func schedule(profile: UserProfile, on date: Date) async {
        let center = UNUserNotificationCenter.current()

        // Remove first so the second `.add` truly replaces. Without
        // this, a schedule call right after a manual cancel can
        // race and leave both requests pending on cold boot.
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your week in Atlas")
        content.body = notificationBody(for: profile)
        content.sound = .default
        content.userInfo = ["deeplink": "peptidex://weekly/current"]
        content.threadIdentifier = identifier

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
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
