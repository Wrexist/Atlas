import Foundation
import UserNotifications

/// "Eat by tomorrow" for meal-prep boxes: the evening before the soonest
/// fridge box's eat-by day. One pending request, replaced whenever the
/// boxes change, so it takes one of iOS's 64 slots (reserved in
/// `NotificationService.isOwnedByAnotherScheduler`). Never asks for
/// permission: without it the colours on the Weekly prep screen do the job.
@MainActor
enum PrepBoxReminderScheduler {

    nonisolated static let identifier = "atlas.weeklyPrep.boxExpiry"

    static func reconcile(boxes: [PrepBoxBatch], recipes: [String: LibraryRecipe]) async {
        cancel()
        let calendar = Calendar.current
        guard await isAuthorised,
              let reminder = WeeklyPrepEngine.nextReminder(for: boxes, recipes: recipes, now: Date(), calendar: calendar)
        else { return }

        let locale = LocalizationManager.shared.effectiveLocale
        let names = reminder.recipeIDs.compactMap { recipes[$0]?.displayName(locale: locale) }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Meal prep boxes to eat by tomorrow", comment: "Notification title the evening before meal-prep boxes expire")
        content.body = ListFormatter.localizedString(byJoining: names)
        content.sound = .default
        content.threadIdentifier = identifier

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        } catch {
            AppLog.notifications.error("Prep box reminder add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
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
