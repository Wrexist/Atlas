import Foundation
@preconcurrency import UserNotifications

@MainActor @Observable
final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private(set) var scheduledCount = 0
    private(set) var requestedCount = 0

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func checkAuthorization() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// Schedules dose reminders, honoring each peptide's individual schedule. Peptides that
    /// share the same (day, time) within a protocol get consolidated into one notification
    /// to stay within the iOS 64-pending-request limit.
    func scheduleNotifications(for protocols: [PeptideProtocol]) {
        center.removeAllPendingNotificationRequests()

        var requests: [UNNotificationRequest] = []

        for proto in protocols where proto.status == .active {
            // Group peptides by (day, time) so co-scheduled peptides combine into one notification.
            var grouped: [TimeslotKey: [Peptide]] = [:]
            for peptide in proto.peptides {
                let schedule = proto.schedule(for: peptide.id)
                for timeString in schedule.preferredTimes {
                    for day in schedule.daysOfWeek {
                        let key = TimeslotKey(day: day, time: timeString)
                        grouped[key, default: []].append(peptide)
                    }
                }
            }

            for (slot, peptides) in grouped {
                guard let (hour, minute) = parseTime(slot.time) else { continue }

                let calendarWeekday = slot.day == 7 ? 1 : slot.day + 1
                var dateComponents = DateComponents()
                dateComponents.weekday = calendarWeekday
                dateComponents.hour = hour
                dateComponents.minute = minute

                let content = UNMutableNotificationContent()
                if peptides.count == 1 {
                    let peptide = peptides[0]
                    content.title = "Time for \(peptide.abbreviation)"
                    content.body = "\(peptide.name) \u{2022} \(peptide.dosageRange)"
                } else {
                    let names = peptides.map(\.abbreviation).joined(separator: ", ")
                    content.title = proto.name
                    content.body = names
                }

                content.sound = .default
                content.categoryIdentifier = "DOSE_REMINDER"
                content.userInfo = [
                    "protocolId": proto.id.uuidString,
                    "hour": hour,
                    "minute": minute,
                ]

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: dateComponents,
                    repeats: true
                )

                let id = "\(proto.id)-\(slot.day)-\(slot.time)"
                requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }

        requestedCount = requests.count
        scheduledCount = min(requests.count, 64)

        let limited = Array(requests.prefix(64))
        for request in limited {
            center.add(request)
        }
    }

    private struct TimeslotKey: Hashable {
        let day: Int
        let time: String
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
        scheduledCount = 0
        requestedCount = 0
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func parseTime(_ timeString: String) -> (Int, Int)? {
        guard let date = Self.timeFormatter.date(from: timeString) else { return nil }
        let calendar = Calendar.current
        return (calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
