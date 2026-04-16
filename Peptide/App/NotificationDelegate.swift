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

                let calendar = Calendar.current
                let uncompleted = dataStore.todayEntries.filter { entry in
                    guard entry.protocolId == protocolId, !entry.completed else { return false }
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
            let content = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            let request = UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: content, trigger: trigger)
            center.add(request)

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
