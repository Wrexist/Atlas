import Foundation

/// Tiny App-Group-backed inbox the widget extension drops "user
/// tapped Log on the live activity" markers into, and the main app
/// drains on next foreground.
///
/// Why a shared inbox instead of a direct DataStore mutation from
/// the widget: an interactive Live Activity intent runs in the
/// widget process, which has no access to SwiftData / CloudKit and
/// shouldn't be replicating the full persistence stack. The widget
/// instead acknowledges the tap by flipping the live activity to
/// `completed` (instant feedback) and writing a marker here. The
/// main app — wherever it next becomes active — reads the marker,
/// toggles the matching `ProtocolEntry`, and clears the inbox.
///
/// Lives in /Shared so the intent (widget process) and
/// `PendingDoseLogProcessor` (app process) hit the same suite.
enum PendingDoseLogStore {

    /// App Group identifier. Mirrors the value in both the app and
    /// widget entitlements — changing it here without updating
    /// those plists is a silent miss, so the value is centralised
    /// in this single constant.
    static let appGroupSuiteName = "group.com.peptidesai.app"

    /// UserDefaults key. The value is a JSON array of
    /// `PendingLog` so multiple taps queue cleanly when the app
    /// is fully suspended.
    private static let inboxKey = "com.peptidesai.app.pendingDoseLogs"

    /// One queued log. Carries `loggedAt` so when the app drains
    /// the inbox it can stamp the entry's `actualTime` with the
    /// moment the user actually tapped, not the moment the app
    /// happens to wake up.
    struct PendingLog: Codable, Hashable {
        let entryId: UUID
        let loggedAt: Date
    }

    /// Append a log marker to the inbox. Safe to call from any
    /// process that holds the App Group entitlement. Idempotent
    /// per (entryId, loggedAt) — re-pushing the exact same marker
    /// is a no-op so a glitchy double-tap doesn't double-log.
    /// Posts a Darwin notification so a foregrounded main app
    /// drains the marker immediately instead of waiting on a
    /// scene-phase transition.
    static func enqueue(_ log: PendingLog, defaults: UserDefaults? = nil) {
        let store = defaults ?? sharedDefaults
        var current = readPending(defaults: store)
        if !current.contains(log) {
            current.append(log)
            write(current, defaults: store)
        }
        postDarwinNotification()
    }

    /// Drains every queued log and returns them in arrival order.
    /// The caller is responsible for applying each one — this
    /// helper just clears the inbox so a second app launch doesn't
    /// re-apply the same logs.
    @discardableResult
    static func drain(defaults: UserDefaults? = nil) -> [PendingLog] {
        let store = defaults ?? sharedDefaults
        let pending = readPending(defaults: store)
        guard !pending.isEmpty else { return [] }
        store.removeObject(forKey: inboxKey)
        return pending
    }

    /// Visibility into the inbox without mutating it. Used by
    /// tests and by the live-activity reconcile pass that wants
    /// to skip an entry already queued for logging.
    static func peek(defaults: UserDefaults? = nil) -> [PendingLog] {
        readPending(defaults: defaults ?? sharedDefaults)
    }

    // MARK: - Internals

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupSuiteName) ?? .standard
    }

    private static func readPending(defaults: UserDefaults) -> [PendingLog] {
        guard let data = defaults.data(forKey: inboxKey) else { return [] }
        return (try? JSONDecoder().decode([PendingLog].self, from: data)) ?? []
    }

    private static func write(_ logs: [PendingLog], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        defaults.set(data, forKey: inboxKey)
    }

    /// Posts a Darwin notification on the inbox name so observers in
    /// other processes (specifically the foregrounded main app) wake
    /// and drain the inbox without waiting for a scene-phase
    /// transition. Best-effort — Darwin notifications drop silently
    /// when no observer is registered, which is exactly the right
    /// behaviour when the app is suspended.
    private static func postDarwinNotification() {
        let name = CrossProcessNotification.pendingDoseLogQueued as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }
}
