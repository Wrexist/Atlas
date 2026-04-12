import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func checkAuthorization() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func scheduleNotifications(for protocols: [PeptideProtocol]) {
        center.removeAllPendingNotificationRequests()

        var requests: [UNNotificationRequest] = []

        for proto in protocols where proto.status == .active {
            for peptide in proto.peptides {
                for timeString in proto.schedule.preferredTimes {
                    for day in proto.schedule.daysOfWeek {
                        guard let (hour, minute) = parseTime(timeString) else { continue }

                        let calendarWeekday = day == 7 ? 1 : day + 1

                        var dateComponents = DateComponents()
                        dateComponents.weekday = calendarWeekday
                        dateComponents.hour = hour
                        dateComponents.minute = minute

                        let content = UNMutableNotificationContent()
                        content.title = "Time for \(peptide.abbreviation)"
                        content.body = "\(peptide.name) \u{2022} \(peptide.dosageRange)"
                        content.sound = .default
                        content.categoryIdentifier = "DOSE_REMINDER"
                        content.userInfo = [
                            "protocolId": proto.id.uuidString,
                            "peptideId": peptide.id.uuidString,
                        ]

                        let trigger = UNCalendarNotificationTrigger(
                            dateMatching: dateComponents,
                            repeats: true
                        )

                        let id = "\(proto.id)-\(peptide.id)-\(day)-\(timeString)"
                        requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    }
                }
            }
        }

        for request in requests.prefix(64) {
            center.add(request)
        }
    }

    func registerCategories() {
        let markAction = UNNotificationAction(
            identifier: "MARK_TAKEN",
            title: "Mark as Taken",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Remind in 15 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "DOSE_REMINDER",
            actions: [markAction, snoozeAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private func parseTime(_ timeString: String) -> (Int, Int)? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: timeString) else { return nil }
        let calendar = Calendar.current
        return (calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
