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

        // Build snooze request outside the Task to avoid sending non-Sendable types across isolation
        var snoozeRequest: UNNotificationRequest?
        if action == "SNOOZE" {
            let content = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            snoozeRequest = UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: content, trigger: trigger)
        }

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
                if let snoozeRequest {
                    try? await UNUserNotificationCenter.current().add(snoozeRequest)
                }

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
