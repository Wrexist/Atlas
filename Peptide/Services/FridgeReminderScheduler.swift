import Foundation
import UserNotifications

/// "Use by tomorrow" for the fridge: the evening before the soonest use-by
/// day, naming what is due. One pending request, replaced whenever the
/// fridge changes, so it takes one of iOS's 64 slots (reserved in
/// `NotificationService.isOwnedByAnotherScheduler`). Never asks for
/// permission itself; the fridge asks once, when a first date is set.
@MainActor
enum FridgeReminderScheduler {

    nonisolated static let identifier = "atlas.fridge.expiry"

    static func reconcile(items: [FridgeItem], products: [UUID: FridgeProduct]) async {
        cancel()
        let calendar = Calendar.current
        guard await isAuthorised,
              let reminder = FridgeEngine.nextReminder(for: items, now: Date(), calendar: calendar)
        else { return }

        let names = reminder.itemIDs.compactMap { id in
            items.first { $0.id == id }.flatMap { products[$0.productID]?.name }
        }
        let content = UNMutableNotificationContent()
        content.title = calendar.isDate(reminder.fireDate, inSameDayAs: reminder.useBy)
            ? String(localized: "Use today", comment: "Notification title the morning fridge items reach their use-by date")
            : String(localized: "Use by tomorrow", comment: "Notification title the evening before fridge items reach their use-by date")
        content.body = ListFormatter.localizedString(byJoining: Array(Set(names)).sorted())
        content.sound = .default
        content.threadIdentifier = identifier

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            NotificationService.shared.trackExternalReminder(identifier, isPending: true)
        } catch {
            AppLog.notifications.error("Fridge reminder add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        NotificationService.shared.trackExternalReminder(identifier, isPending: false)
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
