import Foundation
@preconcurrency import WatchConnectivity
import WatchKit

/// Observable store for the Watch app. Reads WatchData from the shared
/// App Group container and sends mark-complete messages to the iOS app.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published var watchData: WatchData = .empty
    @Published var isSending = false

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private var watchDataURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("watch_data.json")
    }

    override init() {
        super.init()
        loadFromDisk()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func loadFromDisk() {
        guard let url = watchDataURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(WatchData.self, from: data) else { return }
        watchData = decoded
    }

    /// Sends a water-log message to the iOS app. No optimistic local
    /// update: `WatchNutritionSnapshot` carries no water total, so the
    /// Watch has nothing to bump — the phone pushes a fresh snapshot
    /// once it processes the message. Picks the smaller of the two
    /// haptic patterns (.click) — water is a frequent micro-log, not
    /// a milestone.
    func logWater(oz: Int) {
        guard !isSending else { return }
        isSending = true
        WKInterfaceDevice.current().play(.click)
        sendOrQueue([
            "action": WatchMessage.logWater,
            WatchMessage.ozKey: oz,
        ])
    }

    func toggleEntry(_ entry: WatchEntry) {
        guard !isSending else { return }
        isSending = true

        let action = entry.completed ? WatchMessage.markIncomplete : WatchMessage.markComplete
        let message: [String: Any] = [
            "action": action,
            WatchMessage.entryIdKey: entry.id.uuidString,
            WatchMessage.protocolIdKey: entry.protocolId.uuidString
        ]

        // Haptic confirmation: .success on a completion (the satisfying
        // "got it" pattern), .click on an undo so the user can feel the
        // toggle direction without looking. Done before the optimistic
        // state update so the haptic feels coincident with the tap.
        WKInterfaceDevice.current().play(entry.completed ? .click : .success)

        // Optimistically update local state. Preserve the watch-side
        // stats fields (streak / weeklyCompliance / totalDosesLogged /
        // nutrition) that arrived from the phone — the user just
        // toggled a dose, we shouldn't reset the streak to nil or
        // drop the nutrition snapshot on every tap (audit Watch).
        if let index = watchData.todayEntries.firstIndex(where: { $0.id == entry.id }) {
            var updated = watchData.todayEntries
            updated[index].completed.toggle()
            let completed = updated.filter(\.completed).count
            // Preserve the nutrition snapshot — without re-passing it the
            // initializer's default nil hides the Nutrition page (which
            // PeptideWatchApp gates on `nutrition != nil`) until the next
            // phone-side sync arrives. Dose-toggle should never flicker
            // the unrelated nutrition tab off and on.
            watchData = WatchData(
                todayEntries: updated,
                completedToday: completed,
                totalToday: updated.count,
                lastUpdated: Date(),
                currentStreak: watchData.currentStreak,
                weeklyCompliance: watchData.weeklyCompliance,
                totalDosesLogged: watchData.totalDosesLogged,
                nutrition: watchData.nutrition
            )
        }

        sendOrQueue(message)
    }

    /// Delivers a Watch→phone message. When the phone is reachable a
    /// live `sendMessage` gives the fastest round-trip; when it is not
    /// — or the live send fails — the message falls back to
    /// `transferUserInfo`, which the system delivers in the background
    /// once the phone is available again. Previously an unreachable
    /// phone meant the tap was dropped entirely and the optimistic
    /// Watch state was silently overwritten on the next sync.
    private func sendOrQueue(_ message: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { [weak self] _ in
                Task { @MainActor in self?.isSending = false }
            }, errorHandler: { [weak self] _ in
                WCSession.default.transferUserInfo(message)
                Task { @MainActor in self?.isSending = false }
            })
        } else {
            WCSession.default.transferUserInfo(message)
            isSending = false
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = Self.decodeWatchData(from: message) else { return }
        Task { @MainActor in self.watchData = decoded }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let decoded = Self.decodeWatchData(from: context) else { return }
        Task { @MainActor in self.watchData = decoded }
    }

    /// Phone encodes `lastUpdated` as ISO-8601, so the receive-side decoder
    /// must match — a default `JSONDecoder()` expects `.deferredToDate`
    /// (numeric timestamps) and silently drops every push.
    nonisolated private static func decodeWatchData(from payload: [String: Any]) -> WatchData? {
        guard let dict = payload["watchData"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WatchData.self, from: data)
    }
}
