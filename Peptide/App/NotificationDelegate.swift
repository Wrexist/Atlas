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
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let peptideIdStr = userInfo["peptideId"] as? String
        let protocolIdStr = userInfo["protocolId"] as? String
        let originalContent = response.notification.request.content

        Task { @MainActor [dataStore] in
            switch action {
            case "MARK_TAKEN":
                if let peptideIdStr,
                   let peptideId = UUID(uuidString: peptideIdStr),
                   let protocolIdStr,
                   let protocolId = UUID(uuidString: protocolIdStr) {
                    if let entry = dataStore.todayEntries.first(where: {
                        $0.peptide.id == peptideId &&
                        $0.protocolId == protocolId &&
                        !$0.completed
                    }) {
                        dataStore.toggleEntry(entry.id)
                    }
                }

            case "SNOOZE":
                let content = originalContent.mutableCopy() as! UNMutableNotificationContent
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "snooze-\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                try? await UNUserNotificationCenter.current().add(request)

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
