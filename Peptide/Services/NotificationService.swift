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
    /// `nonisolated` so the delegate's nonisolated callback can read it without
    /// a MainActor hop.
    nonisolated static let snoozeIDPrefix = "snooze-"

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
            // Interval cadence: coalesce per-protocol by (occurrence date, time)
            // so two interval-scheduled peptides that share a slot fire one
            // notification, mirroring the weekly path's behaviour.
            appendIntervalRequestsForProtocol(
                proto,
                invalidTimes: &invalidTimesSet,
                into: &pendingRequests
            )

            // Weekly cadence: group peptides by (day, time) so co-scheduled
            // peptides combine into one notification.
            var grouped: [TimeslotKey: [Peptide]] = [:]
            for peptide in proto.peptides {
                let schedule = proto.schedule(for: peptide.id)
                if schedule.isInterval { continue }
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

                let content = makeContent(
                    proto: proto,
                    peptides: peptides,
                    hour: hour,
                    minute: minute
                )

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

    /// Tracks a snooze identifier the delegate just submitted to UNUserNotificationCenter
    /// so subsequent scheduleNotifications calls can preserve it across set-diff.
    /// The actual UN add happens in the delegate's nonisolated callback because
    /// UNUserNotificationCenter is thread-safe and UNNotificationRequest is not Sendable.
    func registerPendingSnooze(id: String) {
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

    /// How many future occurrences to pre-schedule for an every-N-days
    /// protocol. iOS caps total pending requests at 64; this leaves
    /// breathing room for multiple interval protocols + weekly ones.
    /// `rescheduleNotificationsIfEnabled` runs on every app activation, so
    /// the queue gets topped up as occurrences fire.
    private static let intervalLookahead: Int = 12

    private func makeContent(
        proto: PeptideProtocol,
        peptides: [Peptide],
        hour: Int,
        minute: Int
    ) -> UNMutableNotificationContent {
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
        return content
    }

    /// Generates one-shot notification requests for the next several
    /// occurrences of an interval-cadence peptide. Each occurrence produces
    /// one request per preferred time, identified by absolute date so the
    /// set-diff in the main scheduler can clean them up cleanly on the next
    /// reschedule. Coalesces every interval-cadence peptide in `proto` so
    /// that two peptides scheduled for the same date+time fire as a single
    /// notification — the same approach the weekly path takes via
    /// `TimeslotKey`. Without this, an "every 3 days × 5 peptides × 3 doses"
    /// stack would burn 180 of the 64 available iOS slots.
    private func appendIntervalRequestsForProtocol(
        _ proto: PeptideProtocol,
        invalidTimes: inout Set<String>,
        into requests: inout [PendingRequest]
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // (fireDate → peptides firing at that exact moment) for this protocol.
        var slots: [Date: [Peptide]] = [:]

        for peptide in proto.peptides {
            let schedule = proto.schedule(for: peptide.id)
            guard schedule.isInterval, let n = schedule.intervalDays, n >= 1 else { continue }
            let anchor = calendar.startOfDay(for: schedule.intervalAnchor ?? today)

            // Next active day on or after today, anchor-relative.
            let diff = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
            let offsetToNextActive: Int
            if diff <= 0 {
                offsetToNextActive = -diff
            } else {
                let mod = diff % n
                offsetToNextActive = mod == 0 ? 0 : (n - mod)
            }
            guard let firstActive = calendar.date(byAdding: .day, value: offsetToNextActive, to: today) else { continue }

            for occurrence in 0..<Self.intervalLookahead {
                guard let day = calendar.date(byAdding: .day, value: occurrence * n, to: firstActive) else { continue }
                for timeString in schedule.preferredTimes {
                    guard let (hour, minute) = parseTime(timeString) else {
                        if invalidTimes.insert(timeString).inserted {
                            AppLog.notifications.error("Skipping invalid time \"\(timeString, privacy: .public)\" for protocol \(proto.id.uuidString, privacy: .public)")
                        }
                        continue
                    }
                    var components = calendar.dateComponents([.year, .month, .day], from: day)
                    components.hour = hour
                    components.minute = minute
                    guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
                    slots[fireDate, default: []].append(peptide)
                }
            }
        }

        for (fireDate, peptides) in slots {
            // Same peptide may end up here twice if its preferredTimes contain
            // duplicates — dedup by id while preserving first-occurrence order.
            var seen = Set<UUID>()
            let unique = peptides.filter { seen.insert($0.id).inserted }
            let hour = calendar.component(.hour, from: fireDate)
            let minute = calendar.component(.minute, from: fireDate)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let content = makeContent(proto: proto, peptides: unique, hour: hour, minute: minute)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let isoDay = Self.isoDayFormatter.string(from: fireDate)
            let id = "\(proto.id)-int-\(isoDay)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            requests.append(PendingRequest(
                request: request,
                protocolID: proto.id,
                nextFireDate: fireDate
            ))
        }
    }

    /// Hoisted out of the hot path — `ISO8601DateFormatter()` is heavy to
    /// allocate. Used only for stable identifier generation.
    private static let isoDayFormatter = ISO8601DateFormatter()
}
