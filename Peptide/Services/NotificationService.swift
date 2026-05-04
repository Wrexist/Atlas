import Foundation
@preconcurrency import UserNotifications

/// Outcome of a `scheduleNotifications` call. Surfaces what couldn't be scheduled
/// so the UI can warn the user (e.g., "3 reminders couldn't be scheduled").
struct ScheduleReport: Equatable {
    let requested: Int
    let scheduled: Int
    /// Protocol IDs that had at least one request dropped because of the iOS 64
    /// pending-notification limit. A protocol may also still have *some*
    /// reminders scheduled — this just means coverage is partial.
    let droppedProtocolIDs: Set<UUID>
    /// Time strings that couldn't be parsed (e.g., "25:99"). Format is
    /// "h:mm a" — anything else lands here.
    let invalidTimes: [String]
    /// Weekday values outside the ISO 1...7 range that were dropped.
    let invalidWeekdays: [Int]

    static let empty = ScheduleReport(
        requested: 0,
        scheduled: 0,
        droppedProtocolIDs: [],
        invalidTimes: [],
        invalidWeekdays: []
    )

    var hasAnyIssue: Bool {
        !droppedProtocolIDs.isEmpty || !invalidTimes.isEmpty || !invalidWeekdays.isEmpty
    }
}

@MainActor @Observable
final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private(set) var scheduledCount = 0
    private(set) var requestedCount = 0
    private(set) var lastReport: ScheduleReport = .empty

    /// Identifiers we believe are currently pending. Used to compute the delta
    /// against new schedules so we never go through a zero-pending window.
    @ObservationIgnored private var currentIDs: Set<String> = []

    /// iOS limit on pending notification requests per app.
    static let pendingRequestLimit = 64

    /// Prefix used by user-initiated snoozes. scheduleNotifications preserves
    /// IDs starting with this prefix when computing stale-dose removal.
    fileprivate static let snoozeIDPrefix = "snooze-"

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
    ///
    /// Drop policy when over the limit: requests are sorted by next-fire-time
    /// ascending so the user keeps coverage for the soonest doses; the tail is
    /// dropped. Protocols whose requests were partially or fully dropped land
    /// in `ScheduleReport.droppedProtocolIDs` so the UI can surface a banner.
    @discardableResult
    func scheduleNotifications(for protocols: [PeptideProtocol]) -> ScheduleReport {
        var pendingRequests: [PendingRequest] = []
        // Dedup so the report shows distinct issues even when many peptides
        // share the same bad weekday or time string within a protocol.
        var invalidTimesSet: Set<String> = []
        var invalidWeekdaysSet: Set<Int> = []

        for proto in protocols where proto.status == .active {
            // Group peptides by (day, time) so co-scheduled peptides combine into one notification.
            var grouped: [TimeslotKey: [Peptide]] = [:]
            for peptide in proto.peptides {
                let schedule = proto.schedule(for: peptide.id)
                for timeString in schedule.preferredTimes {
                    for day in schedule.daysOfWeek {
                        guard (1...7).contains(day) else {
                            if invalidWeekdaysSet.insert(day).inserted {
                                AppLog.notifications.error("Skipping invalid weekday \(day, privacy: .public) for protocol \(proto.id.uuidString, privacy: .public)")
                            }
                            continue
                        }
                        let key = TimeslotKey(day: day, time: timeString)
                        grouped[key, default: []].append(peptide)
                    }
                }
            }

            for (slot, peptides) in grouped {
                guard let (hour, minute) = parseTime(slot.time) else {
                    if invalidTimesSet.insert(slot.time).inserted {
                        AppLog.notifications.error("Skipping invalid time \"\(slot.time, privacy: .public)\" for protocol \(proto.id.uuidString, privacy: .public)")
                    }
                    continue
                }

                let calendarWeekday = slot.day == 7 ? 1 : slot.day + 1
                var dateComponents = DateComponents()
                dateComponents.weekday = calendarWeekday
                dateComponents.hour = hour
                dateComponents.minute = minute

                let content = UNMutableNotificationContent()
                if let peptide = peptides.first, peptides.count == 1 {
                    content.title = "Time for \(peptide.abbreviation)"
                    let dose = proto.schedule(for: peptide.id).resolvedDose(for: peptide)
                    content.body = "\(peptide.name) \u{2022} \(dose)"
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
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                let nextFire = trigger.nextTriggerDate() ?? Date.distantFuture
                pendingRequests.append(PendingRequest(
                    request: request,
                    protocolID: proto.id,
                    nextFireDate: nextFire
                ))
            }
        }

        // Sort by next-fire-time ascending so we keep coverage for the soonest
        // doses; over-the-limit requests fall off the tail.
        pendingRequests.sort { $0.nextFireDate < $1.nextFireDate }

        let kept = Array(pendingRequests.prefix(Self.pendingRequestLimit))
        let dropped = Array(pendingRequests.dropFirst(Self.pendingRequestLimit))
        let droppedProtocolIDs = Set(dropped.map(\.protocolID))

        let newIDs = Set(kept.map(\.request.identifier))
        // Preserve user-initiated snoozes across reschedules — they're one-shot
        // transient requests that iOS clears after firing, not stale doses.
        let preservedSnoozes = currentIDs.filter { $0.hasPrefix(Self.snoozeIDPrefix) }
        let toRemove = currentIDs.subtracting(newIDs).subtracting(preservedSnoozes)

        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
        for entry in kept {
            center.add(entry.request)
        }

        currentIDs = newIDs.union(preservedSnoozes)
        requestedCount = pendingRequests.count
        scheduledCount = kept.count

        let report = ScheduleReport(
            requested: pendingRequests.count,
            scheduled: kept.count,
            droppedProtocolIDs: droppedProtocolIDs,
            invalidTimes: Array(invalidTimesSet),
            invalidWeekdays: Array(invalidWeekdaysSet)
        )
        lastReport = report

        if report.hasAnyIssue {
            AppLog.notifications.warning(
                "Schedule issues — requested: \(report.requested, privacy: .public), scheduled: \(report.scheduled, privacy: .public), dropped protocols: \(report.droppedProtocolIDs.count, privacy: .public), invalid times: \(report.invalidTimes.count, privacy: .public), invalid weekdays: \(report.invalidWeekdays.count, privacy: .public)"
            )
        }

        return report
    }

    /// Reconciles in-memory tracker against actual pending requests. Call on app
    /// activation to recover from force-quit states where stale pending requests
    /// from a previous run exist that we no longer track.
    func reconcilePendingState() async {
        let pending = await center.pendingNotificationRequests()
        currentIDs = Set(pending.map(\.identifier))
    }

    /// Schedules a one-shot 15-min reminder copy of an existing notification.
    /// Routed through the service so the identifier lands in `currentIDs` and
    /// counts against the same 64-pending-request budget as scheduled doses.
    func scheduleSnooze(from response: UNNotificationResponse) {
        guard let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        let id = "\(Self.snoozeIDPrefix)\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
        currentIDs.insert(id)
    }

    private struct TimeslotKey: Hashable {
        let day: Int
        let time: String
    }

    private struct PendingRequest {
        let request: UNNotificationRequest
        let protocolID: UUID
        let nextFireDate: Date
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
        currentIDs.removeAll()
        scheduledCount = 0
        requestedCount = 0
        lastReport = .empty
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
