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

    /// Slice of `pendingRequestLimit` reserved for habit reminders.
    /// Habit reminders and dose reminders share iOS's global 64-slot
    /// budget; capping habits here (and reserving the remainder for
    /// doses in `scheduleNotifications`) stops a habit-heavy user from
    /// silently evicting dose reminders past the limit.
    static let habitRequestLimit = 32

    /// Prefix used by user-initiated snoozes. scheduleNotifications preserves
    /// IDs starting with this prefix when computing stale-dose removal.
    /// `nonisolated` so the delegate's nonisolated callback can read it without
    /// a MainActor hop.
    nonisolated static let snoozeIDPrefix = "snooze-"

    /// Prefix used by habit reminders so the peptide scheduler's set-diff
    /// doesn't sweep them away (and vice versa). Each habit reserves up to
    /// 7 weekday slots, kept distinct from the protocol/snooze namespaces.
    nonisolated static let habitIDPrefix = "habit-"

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .private)")
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

        // Reserve room for habit reminders + active snoozes already in
        // iOS's global 64-slot budget. Dose reminders are the priority
        // (a missed dose reminder matters more than a missed habit
        // check-in), but they must not be scheduled past the slots the
        // habit/snooze namespaces already occupy or iOS silently drops
        // whichever requests are added last.
        let reservedSlots = currentIDs.filter {
            $0.hasPrefix(Self.habitIDPrefix) || $0.hasPrefix(Self.snoozeIDPrefix)
        }.count
        let doseLimit = max(0, Self.pendingRequestLimit - reservedSlots)
        let kept = Array(pendingRequests.prefix(doseLimit))
        let dropped = Array(pendingRequests.dropFirst(doseLimit))
        let droppedProtocolIDs = Set(dropped.map(\.protocolID))

        let newIDs = Set(kept.map(\.request.identifier))
        // Preserve user-initiated snoozes across reschedules — they're one-shot
        // transient requests that iOS clears after firing, not stale doses.
        // Habit reminders live in a separate namespace; their own scheduler
        // owns their lifecycle so we must not sweep them here.
        let preservedSnoozes = currentIDs.filter { $0.hasPrefix(Self.snoozeIDPrefix) }
        let preservedHabits = currentIDs.filter { $0.hasPrefix(Self.habitIDPrefix) }
        let toRemove = currentIDs
            .subtracting(newIDs)
            .subtracting(preservedSnoozes)
            .subtracting(preservedHabits)

        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
        for entry in kept {
            center.add(entry.request)
        }

        currentIDs = newIDs.union(preservedSnoozes).union(preservedHabits)
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

    /// Schedules one calendar reminder per scheduled day per habit. Only
    /// habits with a non-nil `reminderTime` produce requests; the rest are
    /// silently skipped. Uses the `habit-` ID namespace so the peptide
    /// scheduler's set-diff leaves them alone.
    ///
    /// Schedule mapping:
    ///   - `.daily` and `.timesPerWeek` → one repeating request that fires
    ///     every day at the chosen hour:minute. Flexible cadences nudge the
    ///     user daily; if they've already hit the week's count, they just
    ///     dismiss.
    ///   - `.weekdays(set)` → one repeating request per weekday so the
    ///     reminder only fires on the days the habit is actually due.
    @discardableResult
    func scheduleHabitReminders(for habits: [Habit]) -> Int {
        let stale = currentIDs.filter { $0.hasPrefix(Self.habitIDPrefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
            currentIDs.subtract(stale)
        }

        var scheduled = 0
        let calendar = Calendar.current

        for habit in habits where !habit.archived {
            if scheduled >= Self.habitRequestLimit { break }
            guard let reminderTime = habit.reminderTime else { continue }
            let hour = calendar.component(.hour, from: reminderTime)
            let minute = calendar.component(.minute, from: reminderTime)

            let content = UNMutableNotificationContent()
            content.title = habit.name
            if let target = habit.targetValue {
                content.body = String(localized: "Today's goal: \(target)", comment: "Habit reminder body — countable habits, value is the target.")
            } else {
                content.body = String(localized: "Time to check in.", comment: "Habit reminder body — boolean habits.")
            }
            content.sound = .default
            content.userInfo = ["habitId": habit.id.uuidString]

            let weekdays: [Int?]
            switch habit.schedule {
            case .daily, .timesPerWeek:
                // nil weekday → matches every day.
                weekdays = [nil]
            case .weekdays(let days):
                weekdays = days.map { Optional($0.rawValue) }
            }

            for weekday in weekdays {
                if scheduled >= Self.habitRequestLimit { break }
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                if let weekday { components.weekday = weekday }
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let suffix = weekday.map(String.init) ?? "daily"
                let id = "\(Self.habitIDPrefix)\(habit.id)-\(suffix)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request)
                currentIDs.insert(id)
                scheduled += 1
            }
        }
        return scheduled
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
        // Three snooze options instead of one — long-press on the
        // notification banner reveals up to 4 actions on iOS, so
        // we can give the user a real choice instead of one fixed
        // 15-min default. The action identifier carries the
        // duration in minutes so the delegate can branch with a
        // single shared handler.
        let snooze15 = UNNotificationAction(
            identifier: "SNOOZE_15",
            title: "Remind in 15 min",
            options: []
        )
        let snooze30 = UNNotificationAction(
            identifier: "SNOOZE_30",
            title: "Remind in 30 min",
            options: []
        )
        let snooze60 = UNNotificationAction(
            identifier: "SNOOZE_60",
            title: "Remind in 1 hour",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "DOSE_REMINDER",
            actions: [markAction, snooze15, snooze30, snooze60],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    /// Returns the snooze duration (in seconds) for a notification
    /// action identifier, or nil when the identifier isn't a
    /// snooze. Lets `NotificationDelegate` share one
    /// reschedule code path across the three durations.
    ///
    /// `nonisolated` because this is a pure switch over the
    /// identifier string — no actor state is touched. The default
    /// MainActor isolation from the enclosing class would make
    /// `NotificationDelegate`'s synchronous call site illegal
    /// under Swift 6.
    nonisolated static func snoozeDuration(forActionIdentifier identifier: String) -> TimeInterval? {
        switch identifier {
        case "SNOOZE", "SNOOZE_15":  return 15 * 60
        case "SNOOZE_30":            return 30 * 60
        case "SNOOZE_60":            return 60 * 60
        default:                     return nil
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        currentIDs.removeAll()
        scheduledCount = 0
        requestedCount = 0
        lastReport = .empty
    }

    /// Wipes only the protocol-dose reminders, leaving habit reminders and
    /// pending snoozes intact. Used when the user disables dose reminders —
    /// flipping that switch shouldn't silently break their habit reminders.
    func cancelProtocolReminders() {
        let toKeep = currentIDs.filter {
            $0.hasPrefix(Self.snoozeIDPrefix) || $0.hasPrefix(Self.habitIDPrefix)
        }
        let toRemove = currentIDs.subtracting(toKeep)
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
        currentIDs = toKeep
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
        // Group all reminders for a single protocol into one thread
        // so iOS stacks them in Notification Center instead of
        // showing N flat entries. Cuts visual fatigue for users on
        // a multi-dose-per-day schedule.
        content.threadIdentifier = proto.id.uuidString
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
    /// Anchored to UTC so notification-request IDs stay stable across
    /// DST flips and travel — letting the device timezone leak into the
    /// ID string used to fall out of sync with the set-diff on
    /// `pendingRequests`, leaving stale notifications scheduled.
    nonisolated(unsafe) private static let isoDayFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
