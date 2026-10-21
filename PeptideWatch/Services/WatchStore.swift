import Foundation
@preconcurrency import WatchConnectivity
import WatchKit
import WidgetKit

/// Observable store for the Watch app. Reads WatchData from the shared
/// App Group container and sends mark-complete messages to the iOS app.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    /// Shared so the WatchConnectivity background task reaches the same
    /// store the UI renders.
    static let shared = WatchStore()

    /// The latest snapshot as it reads now (see `WatchData.forDisplay`).
    @Published private(set) var watchData: WatchData = .empty
    @Published private(set) var isSending = false

    /// Bumped on every guarded send so a stale release from a prior send
    /// can't clear `isSending` out from under a newer in-flight send.
    private var sendToken = 0

    /// How long a guarded tap holds the controls after it is delivered or
    /// queued, so a double tap can't log the next set or a second glass
    /// even when the phone answers at once or is out of reach.
    private static let minimumHold: Duration = .milliseconds(600)

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

    private override init() {
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
        watchData = decoded.forDisplay(at: Date())
    }

    /// Re-reads the snapshot against the clock, so yesterday's doses and
    /// a workout whose end never arrived clear without a push.
    func refreshForNow() {
        watchData = watchData.forDisplay(at: Date())
    }

    /// Keeps a WatchConnectivity background launch alive until the phone's
    /// queued context has arrived, then adopts it, so the complications
    /// update without the app being opened.
    func drainPendingContent() async {
        let session = WCSession.default
        while !Task.isCancelled, session.activationState != .activated || session.hasContentPending {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if let decoded = Self.decodeWatchData(from: session.receivedApplicationContext) {
            adoptIfNewer(decoded)
        }
    }

    /// Adopts a stored context only when it is newer than the snapshot
    /// shown, so a relaunch while the phone is away keeps the taps made
    /// since that push instead of reverting them.
    private func adoptIfNewer(_ data: WatchData) {
        guard data.lastUpdated > watchData.lastUpdated else { return }
        apply(data)
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
        watchData = data.forDisplay(at: Date())
        persistToDisk(data)
        WidgetCenter.shared.reloadAllTimelines()
        scheduleRestEndHaptic(for: data.workout)
    }

    /// Sends a workout tap to the phone and shows its likely result at
    /// once, so logging a set never waits on the round trip. The phone's
    /// next push replaces the guess with what it actually applied.
    func sendWorkout(_ command: WatchWorkoutCommand) {
        guard let workout = watchData.workout else { return }
        // Whole seconds, as the phone's push carries them, so the guessed
        // rest end matches the pushed one exactly instead of re-arming the
        // haptic and nudging the countdown on every push.
        let issuedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let request = WatchWorkoutRequest(sessionId: workout.sessionId, command: command, issuedAt: issuedAt)
        guard let payload = request.encoded() else { return }
        // A second "Complete set" tap would log the next set too, since
        // the first one already moved the page on, and a second "Add set"
        // would add another set under a fresh id. Held like a dose toggle.
        let guarded = switch command {
        case .completeSet, .addSet: true
        default: false
        }
        if guarded {
            guard !isSending else { return }
            isSending = true
        }
        if case .completeSet = command { play(.success) } else { play(.click) }
        apply(watchData.replacingWorkout(workout.applying(command, at: issuedAt)))
        sendOrQueue([
            "action": WatchMessage.workout,
            WatchMessage.workoutRequestKey: payload,
        ], guarded: guarded)
    }

    /// Plays a tap confirmation unless the user turned Haptic Feedback off
    /// on the phone.
    private func play(_ haptic: WKHapticType) {
        guard watchData.hapticsEnabled ?? true else { return }
        WKInterfaceDevice.current().play(haptic)
    }

    /// The rest countdown currently armed, so a push that leaves the rest
    /// unchanged doesn't restart the wait.
    private var armedRestEnd: Date?
    private var restHapticTask: Task<Void, Never>?

    /// Taps the wrist when the rest ends while the app is open. With the
    /// app closed, the phone's own "Time to lift" notification reaches the
    /// watch instead. Plays regardless of the Haptic Feedback setting: it
    /// is the alert itself, not a tap confirmation. A wait that resumes
    /// after the app was suspended past the rest end stays silent rather
    /// than buzzing minutes late.
    private func scheduleRestEndHaptic(for workout: WatchWorkoutSnapshot?) {
        let endsAt = workout.flatMap { $0.isResting(at: Date()) ? $0.rest?.endsAt : nil }
        guard endsAt != armedRestEnd else { return }
        armedRestEnd = endsAt
        restHapticTask?.cancel()
        guard let endsAt else { return }
        restHapticTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled, self?.armedRestEnd == endsAt,
                  endsAt.timeIntervalSinceNow > -2 else { return }
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
    func logWater(oz: Int) {
        guard !isSending else { return }
        isSending = true
        play(.click)
        sendOrQueue([
            "action": WatchMessage.logWater,
            WatchMessage.ozKey: oz,
        ], guarded: true)
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
        play(entry.completed ? .click : .success)

        // Optimistic update. `replacingEntries` carries every other field
        // forward, so a tap never blanks the score, habits, nutrition or
        // vitals until the phone's next push.
        if let index = watchData.todayEntries.firstIndex(where: { $0.id == entry.id }) {
            var updated = watchData.todayEntries
            updated[index].completed.toggle()
            apply(watchData.replacingEntries(updated))
        }

        sendOrQueue(message, guarded: true)
    }

    /// Delivers a Watch→phone message. When the phone is reachable a
    /// live `sendMessage` gives the fastest round-trip; when it is not
    /// — or the live send fails — the message falls back to
    /// `transferUserInfo`, which the system delivers in the background
    /// once the phone is available again. Previously an unreachable
    /// phone meant the tap was dropped entirely and the optimistic
    /// Watch state was silently overwritten on the next sync.
    ///
    /// Every message carries an id, so the phone applies a live send and
    /// its fallback copy once, and the tap time, so a queued command is
    /// logged when it was made. A `guarded` send is one that set
    /// `isSending`; only its own delivery releases the hold.
    private func sendOrQueue(_ message: [String: Any], guarded: Bool) {
        let message = message.merging([
            WatchMessage.messageIdKey: UUID().uuidString,
            WatchMessage.issuedAtKey: Date().timeIntervalSince1970,
        ]) { _, stamped in stamped }
        let token = guarded ? beginGuardedSend() : nil

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { [weak self] _ in
                Task { @MainActor in self?.releaseSending(token) }
            }, errorHandler: { [weak self] _ in
                WCSession.default.transferUserInfo(message)
                Task { @MainActor in self?.releaseSending(token) }
            })
        } else {
            WCSession.default.transferUserInfo(message)
            releaseSending(token)
        }
    }

    /// Starts a guarded send's watchdog. WCSession can hang if the phone
    /// deactivates mid-flight and neither the reply nor the error handler
    /// fires, which would leave `isSending` true and disable every further
    /// Watch tap. Forces it back after 10s; the token makes a newer send
    /// immune.
    private func beginGuardedSend() -> Int {
        sendToken &+= 1
        let token = sendToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if self.sendToken == token { self.isSending = false }
        }
        return token
    }

    /// Ends a guarded send's hold after `minimumHold`. Nil for an
    /// unguarded send, whose reply must not re-enable a tap still in flight.
    private func releaseSending(_ token: Int?) {
        guard let token else { return }
        Task { @MainActor in
            try? await Task.sleep(for: Self.minimumHold)
            if self.sendToken == token { self.isSending = false }
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
        Task { @MainActor in self.adoptIfNewer(decoded) }
    }

    /// A live push of the same second as the shown snapshot is still
    /// adopted (the wire format keeps whole seconds); an older one that
    /// arrives late would revert newer taps, so it is dropped.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let decoded = Self.decodeWatchData(from: context) else { return }
        Task { @MainActor in
            guard decoded.lastUpdated >= self.watchData.lastUpdated else { return }
            self.apply(decoded)
        }
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
