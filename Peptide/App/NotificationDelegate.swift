import SwiftUI
import UserNotifications

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
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        Task { @MainActor [dataStore] in
            switch action {
            case "MARK_TAKEN":
                if let peptideIdStr = userInfo["peptideId"] as? String,
                   let peptideId = UUID(uuidString: peptideIdStr),
                   let protocolIdStr = userInfo["protocolId"] as? String,
                   let protocolId = UUID(uuidString: protocolIdStr) {
                    let calendar = Calendar.current
                    if let entry = dataStore.todayEntries.first(where: {
                        $0.peptide.id == peptideId &&
                        $0.protocolId == protocolId &&
                        !$0.completed
                    }) {
                        dataStore.toggleEntry(entry.id)
                    }
                }

            case "SNOOZE":
                let content = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "snooze-\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)

            default:
                break
            }
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
