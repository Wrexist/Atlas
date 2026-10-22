import Foundation
@preconcurrency import WatchConnectivity
import WatchKit
import WidgetKit

/// Observable store for the Watch app. Reads WatchData from the shared
/// App Group container and sends mark-complete messages to the iOS app.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published var watchData: WatchData = .empty
    @Published var isSending = false

    /// Bumped on every send so a stale watchdog from a prior send can't
    /// clear `isSending` out from under a newer in-flight send.
    private var sendToken = 0

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

    /// Adopts a snapshot: publishes it, mirrors it into the watch's own
    /// App Group container, and asks WidgetKit to redraw.
    ///
    /// The mirror is what makes the complications work at all. Both
    /// `PeptideWatchWidgets` providers — and `loadFromDisk` above — read
    /// `watch_data.json` from the *watch's* container, but the only
    /// writer was the phone's `WatchSyncService`. App Group containers
    /// are per-device, so that file never crossed the wire and every
    /// complication rendered its empty state forever.
    private func apply(_ data: WatchData) {
        watchData = data
        persistToDisk(data)
        WidgetCenter.shared.reloadAllTimelines()
        scheduleRestEndHaptic(for: data.workout)
    }

    /// Sends a workout tap to the phone and shows its likely result at
    /// once, so logging a set never waits on the round trip. The phone's
    /// next push replaces the guess with what it actually applied.
    func sendWorkout(_ command: WatchWorkoutCommand) {
        guard let workout = watchData.workout else { return }
        let request = WatchWorkoutRequest(sessionId: workout.sessionId, command: command, issuedAt: Date())
        guard let payload = request.encoded() else { return }
        if case .completeSet = command {
            // A second tap would log the next set too, since the first
            // one already moved the page on. Held like a dose toggle.
            guard !isSending else { return }
            isSending = true
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
        apply(watchData.replacingWorkout(workout.applying(command, at: request.issuedAt)))
        sendOrQueue([
            "action": WatchMessage.workout,
            WatchMessage.workoutRequestKey: payload,
        ])
    }

    /// The rest countdown currently armed, so a push that leaves the rest
    /// unchanged doesn't restart the wait.
    private var armedRestEnd: Date?
    private var restHapticTask: Task<Void, Never>?

    /// Taps the wrist when the rest ends while the app is open. With the
    /// app closed, the phone's own "Time to lift" notification reaches the
    /// watch instead.
    private func scheduleRestEndHaptic(for workout: WatchWorkoutSnapshot?) {
        let endsAt = workout.flatMap { $0.isResting(at: Date()) ? $0.rest?.endsAt : nil }
        guard endsAt != armedRestEnd else { return }
        armedRestEnd = endsAt
        restHapticTask?.cancel()
        guard let endsAt else { return }
        restHapticTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled, self?.armedRestEnd == endsAt else { return }
            WKInterfaceDevice.current().play(.notification)
        }
    }

    /// Best effort by design: the published state is already updated, so
    /// a failed write costs the complications and the next cold launch,
    /// not the running app.
    private func persistToDisk(_ data: WatchData) {
        guard let url = watchDataURL,
              let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    /// Sends a water-log message to the iOS app. No optimistic local
    /// update: `WatchNutritionSnapshot` carries no water total, so the
    /// Watch has nothing to bump — the phone pushes a fresh snapshot
    /// once it processes the message. Picks the smaller of the two
    /// haptic patterns (.click) — water is a frequent micro-log, not
    /// a milestone.
    func logWater(fluidOunces: Double) {
        guard !isSending else { return }
        isSending = true
        WKInterfaceDevice.current().play(.click)
        sendOrQueue([
            "action": WatchMessage.logWater,
            WatchMessage.fluidOuncesKey: fluidOunces,
            WatchMessage.ozKey: Int(fluidOunces.rounded()),
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

        // Optimistic update. `replacingEntries` carries every other field
        // forward, so a tap never blanks the score, habits, nutrition or
        // vitals until the phone's next push.
        if let index = watchData.todayEntries.firstIndex(where: { $0.id == entry.id }) {
            var updated = watchData.todayEntries
            updated[index].completed.toggle()
            apply(watchData.replacingEntries(updated))
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
        // Watchdog: WCSession can hang if the phone deactivates mid-flight
        // and neither the reply nor the error handler fires, which would
        // leave `isSending` true and disable every further Watch tap. Force
        // it back after 10s — the token guard makes a newer send immune.
        sendToken &+= 1
        let token = sendToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self.sendToken == token, self.isSending { self.isSending = false }
        }

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
    /// Picks up the context the phone pushed while this app wasn't
    /// running. `didReceiveApplicationContext` only fires for pushes that
    /// arrive after activation, so without this a cold launch showed the
    /// disk cache until the phone happened to push again.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated,
              let decoded = Self.decodeWatchData(from: session.receivedApplicationContext) else { return }
        Task { @MainActor in self.apply(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = Self.decodeWatchData(from: message) else { return }
        Task { @MainActor in self.apply(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let decoded = Self.decodeWatchData(from: context) else { return }
        Task { @MainActor in self.apply(decoded) }
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
