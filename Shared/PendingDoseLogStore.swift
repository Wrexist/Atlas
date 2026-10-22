import Foundation
import OSLog

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

    /// App Group identifier — sourced from the single `AppGroup`
    /// constant in `Shared/` so it can't drift from the other
    /// shared-container call sites.
    static let appGroupSuiteName = AppGroup.identifier

    /// Each queued log lives under its own key with this prefix, so
    /// the widget enqueuing and the app draining never read-modify-
    /// write one shared value — a tap written between the app's read
    /// and its removal would otherwise be erased.
    private static let inboxKeyPrefix = "com.peptidesai.app.pendingDoseLog."

    /// The single JSON-array inbox earlier builds wrote; drained once
    /// so taps queued before an update still land.
    private static let legacyInboxKey = "com.peptidesai.app.pendingDoseLogs"

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
    /// per (entryId, loggedAt) — the key is derived from both, so
    /// re-pushing the exact same marker overwrites itself and a
    /// glitchy double-tap doesn't double-log.
    /// Posts a Darwin notification so a foregrounded main app
    /// drains the marker immediately instead of waiting on a
    /// scene-phase transition.
    static func enqueue(_ pending: PendingLog, defaults: UserDefaults? = nil) {
        let store = defaults ?? sharedDefaults
        do {
            store.set(try JSONEncoder().encode(pending), forKey: key(for: pending))
        } catch {
            log.error("inbox encode failed; dose tap not queued: \(error.localizedDescription, privacy: .public)")
        }
        postDarwinNotification()
    }

    /// Drains every queued log and returns them in tap order.
    /// The caller is responsible for applying each one — this
    /// helper removes exactly the keys it read, so a tap enqueued
    /// mid-drain stays queued for the next pass.
    @discardableResult
    static func drain(defaults: UserDefaults? = nil) -> [PendingLog] {
        let store = defaults ?? sharedDefaults
        let queued = readQueued(store)
        queued.keys.forEach { store.removeObject(forKey: $0) }
        return inTapOrder(queued)
    }

    /// Visibility into the inbox without mutating it. Used by
    /// tests and by the live-activity reconcile pass that wants
    /// to skip an entry already queued for logging.
    static func peek(defaults: UserDefaults? = nil) -> [PendingLog] {
        inTapOrder(readQueued(defaults ?? sharedDefaults))
    }

    // MARK: - Internals

    /// Local logger — `AppLog` lives in the main app target and this
    /// file also compiles into the widget/Watch extensions, so it
    /// mirrors the same subsystem/category convention directly.
    private static let log = Logger(subsystem: "com.peptidesai.app", category: "PendingDoseLog")

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupSuiteName) ?? .standard
    }

    private static func key(for pending: PendingLog) -> String {
        "\(inboxKeyPrefix)\(pending.entryId.uuidString)@\(pending.loggedAt.timeIntervalSinceReferenceDate)"
    }

    /// Every queued log keyed by the defaults key holding it. A key
    /// that fails to decode maps to no logs, so draining still clears it.
    private static func readQueued(_ defaults: UserDefaults) -> [String: [PendingLog]] {
        var queued: [String: [PendingLog]] = [:]
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(inboxKeyPrefix) || key == legacyInboxKey {
            queued[key] = decode(value as? Data, isLegacy: key == legacyInboxKey)
        }
        return queued
    }

    private static func decode(_ data: Data?, isLegacy: Bool) -> [PendingLog] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        do {
            return try isLegacy
                ? decoder.decode([PendingLog].self, from: data)
                : [decoder.decode(PendingLog.self, from: data)]
        } catch {
            // A corrupted marker means a queued dose tap is about to be
            // dropped — that must be visible in Console, not silent.
            log.error("inbox decode failed; dropping queued log: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func inTapOrder(_ queued: [String: [PendingLog]]) -> [PendingLog] {
        Set(queued.values.joined()).sorted { $0.loggedAt < $1.loggedAt }
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
