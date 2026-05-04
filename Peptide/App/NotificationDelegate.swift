import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let action = response.actionIdentifier

        switch action {
        case "MARK_TAKEN":
            let userInfo = response.notification.request.content.userInfo
            let protocolIdStr = userInfo["protocolId"] as? String
            let scheduledHour = userInfo["hour"] as? Int
            let scheduledMinute = userInfo["minute"] as? Int

            Task { @MainActor [dataStore] in
                defer { completionHandler() }

                guard let protocolIdStr,
                      let protocolId = UUID(uuidString: protocolIdStr),
                      let hour = scheduledHour,
                      let minute = scheduledMinute else { return }

                // Search the last 24h, not just today, so a snooze that fires
                // after midnight still toggles yesterday's scheduled dose.
                let calendar = Calendar.current
                let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
                let uncompleted = dataStore.entries.filter { entry in
                    guard entry.protocolId == protocolId,
                          !entry.completed,
                          entry.date >= cutoff else { return false }
                    let entryHour = calendar.component(.hour, from: entry.date)
                    let entryMinute = calendar.component(.minute, from: entry.date)
                    return entryHour == hour && entryMinute == minute
                }
                for entry in uncompleted {
                    dataStore.toggleEntry(entry.id)
                }
            }
            return

        case "SNOOZE":
            Task { @MainActor in
                NotificationService.shared.scheduleSnooze(from: response)
            }

        default:
            break
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
