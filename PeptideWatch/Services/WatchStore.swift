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
    /// A workout the Watch runs by itself, started while the phone was out
    /// of reach. While it runs it owns the Workout page.
    @Published private(set) var offlineWorkout: WatchOfflineWorkout?
    /// Finished Watch-run workouts the phone hasn't confirmed filing.
    @Published private(set) var offlineOutbox: [WatchOfflineWorkout] = []
    /// Whether the phone answers live messages right now. Only while it
    /// doesn't can a workout start on the wrist; otherwise the phone owns it.
    @Published private(set) var isPhoneReachable = false

    /// The workout the Workout page shows: the Watch's own, else the phone's.
    var displayedWorkout: WatchWorkoutSnapshot? {
        offlineWorkout?.snapshot ?? watchData.workout
    }

    var canStartOfflineWorkout: Bool {
        offlineWorkout == nil && watchData.workout == nil && !isPhoneReachable
    }

    /// Bumped on every guarded send so a stale release from a prior send
    /// can't clear `isSending` out from under a newer in-flight send.
    private var sendToken = 0

    /// Long enough for activation and a queued context to land.
    private static let drainTimeout: TimeInterval = 10

    /// Commands tapped before the session finished activating. Neither
    /// send path works until then, so they wait here and go out in order.
    private var awaitingActivation: [[String: Any]] = []

    /// Marks a command already re-queued once after a failed transfer, so
    /// a transfer that keeps failing is not retried forever. The phone
    /// ignores the key.
    nonisolated private static let retriedKey = "retried"

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

    /// The Watch-run workout and the outbox, in the app's own container:
    /// nothing else on the Watch reads them.
    private var offlineStateURL: URL {
        URL.documentsDirectory.appending(path: "offline_workouts.json")
    }

    private struct OfflineState: Codable {
        var active: WatchOfflineWorkout?
        var outbox: [WatchOfflineWorkout]
    }

    private override init() {
        super.init()
        loadFromDisk()
        loadOfflineState()
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
    /// update without the app being opened. Bounded, so a session that
    /// never activates ends the task promptly instead of at expiry, which
    /// counts against the background budget.
    func drainPendingContent() async {
        let session = WCSession.default
        let deadline = Date.now.addingTimeInterval(Self.drainTimeout)
        while !Task.isCancelled, Date.now < deadline,
              session.activationState != .activated || session.hasContentPending {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated else { return }
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
        scheduleRestEndHaptic(for: displayedWorkout)
        pruneOutbox(syncedIDs: data.syncedWorkoutIDs)
    }

    /// Sends a workout tap to the phone and shows its likely result at
    /// once, so logging a set never waits on the round trip. The phone's
    /// next push replaces the guess with what it actually applied.
    func sendWorkout(_ command: WatchWorkoutCommand) {
        if offlineWorkout != nil {
            applyOffline(command)
            return
        }
        guard let workout = watchData.workout else { return }
        let issuedAt = Self.tapTime()
        let request = WatchWorkoutRequest(sessionId: workout.sessionId, command: command, issuedAt: issuedAt)
        guard let payload = request.encoded() else { return }
        let guarded = Self.holdsControls(command)
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

    /// Whole seconds, as the phone's push carries them, so the guessed
    /// rest end matches the pushed one exactly instead of re-arming the
    /// haptic and nudging the countdown on every push.
    private static func tapTime() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    /// A second "Complete set" tap would log the next set too, since the
    /// first one already moved the page on, and a second "Add set" would
    /// add another set under a fresh id. Held like a dose toggle.
    private static func holdsControls(_ command: WatchWorkoutCommand) -> Bool {
        switch command {
        case .completeSet, .addSet: true
        default: false
        }
    }

    // MARK: - Workouts without the phone

    /// Starts a workout the Watch owns, from a cached routine or empty.
    /// Offered only while the phone is out of reach and runs none itself.
    func startOfflineWorkout(_ routine: WatchRoutine?) {
        guard canStartOfflineWorkout else { return }
        play(.start)
        updateOffline(WatchOfflineWorkout(routine: routine, at: Self.tapTime()))
    }

    func addOfflineLift(_ lift: WatchLift) {
        guard let workout = offlineWorkout else { return }
        play(.click)
        updateOffline(workout.adding(lift))
    }

    /// Moves the workout to the outbox and hands it to WatchConnectivity,
    /// which delivers it whenever the phone is next in reach.
    func finishOfflineWorkout() {
        guard let workout = offlineWorkout, workout.hasLoggedWork else { return }
        play(.success)
        offlineOutbox = WatchOfflineSyncEngine.enqueue(workout.finished(at: Date()), into: offlineOutbox)
        updateOffline(nil)
        sendOfflineOutbox()
    }

    func discardOfflineWorkout() {
        guard offlineWorkout != nil else { return }
        play(.click)
        updateOffline(nil)
    }

    /// The Watch-run counterpart of `sendWorkout`: the same tap, haptic
    /// and double-tap hold, applied here and nowhere else.
    private func applyOffline(_ command: WatchWorkoutCommand) {
        guard let workout = offlineWorkout else { return }
        if Self.holdsControls(command) {
            guard !isSending else { return }
            isSending = true
            releaseSending(beginGuardedSend())
        }
        if case .completeSet = command { play(.success) } else { play(.click) }
        updateOffline(workout.applying(command, at: Self.tapTime()))
    }

    private func updateOffline(_ workout: WatchOfflineWorkout?) {
        offlineWorkout = workout
        persistOfflineState()
        scheduleRestEndHaptic(for: displayedWorkout)
    }

    /// Hands every unconfirmed workout to WatchConnectivity, except one it
    /// is still delivering. Runs on finish and on each activation, so a
    /// workout the phone received but couldn't save goes out again.
    private func sendOfflineOutbox() {
        let session = WCSession.default
        guard session.activationState == .activated, !offlineOutbox.isEmpty else { return }
        let inFlight = Set(session.outstandingUserInfoTransfers.compactMap {
            WatchOfflineSyncEngine.workoutID(in: $0.userInfo)
        })
        for workout in WatchOfflineSyncEngine.toSend(offlineOutbox, inFlight: inFlight) {
            guard let message = WatchOfflineSyncEngine.message(for: workout) else { continue }
            session.transferUserInfo(message)
        }
    }

    /// Lets go of the workouts the phone's push says it has filed.
    private func pruneOutbox(syncedIDs: [UUID]?) {
        guard let syncedIDs, !offlineOutbox.isEmpty else { return }
        let remaining = WatchOfflineSyncEngine.pruned(offlineOutbox, syncedIDs: syncedIDs)
        guard remaining.count != offlineOutbox.count else { return }
        offlineOutbox = remaining
        persistOfflineState()
    }

    private func loadOfflineState() {
        guard let data = try? Data(contentsOf: offlineStateURL),
              let state = try? JSONDecoder().decode(OfflineState.self, from: data) else { return }
        offlineWorkout = state.active
        offlineOutbox = state.outbox
    }

    /// Written on every tap: this file is the only copy of a workout the
    /// phone hasn't seen, so it must survive the app being closed mid-set.
    private func persistOfflineState() {
        let state = OfflineState(active: offlineWorkout, outbox: offlineOutbox)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: offlineStateURL, options: .atomic)
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
    /// app suspended, only the phone's "Time to lift" notification can
    /// reach the wrist, and only while the phone is locked. Plays regardless of the Haptic Feedback setting: it
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
    func logWater(fluidOunces: Double) {
        guard !isSending else { return }
        isSending = true
        play(.click)
        sendOrQueue([
            "action": WatchMessage.logWater,
            WatchMessage.fluidOuncesKey: fluidOunces,
            WatchMessage.ozKey: Int(fluidOunces.rounded()),
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
        let session = WCSession.default

        guard session.activationState == .activated else {
            awaitingActivation.append(message)
            releaseSending(token)
            return
        }
        // A live message can overtake commands still queued as transfers,
        // so an undo would reach the phone before the tap it undoes. While
        // any transfer is outstanding, queue behind it to keep one order.
        if session.isReachable, session.outstandingUserInfoTransfers.isEmpty {
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

    /// Sends the commands tapped before activation, oldest first, through
    /// the queued channel that keeps their order.
    private func flushAwaitingActivation() {
        let queued = awaitingActivation
        awaitingActivation.removeAll()
        queued.forEach { WCSession.default.transferUserInfo($0) }
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
        guard state == .activated else { return }
        let decoded = Self.decodeWatchData(from: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
            self.flushAwaitingActivation()
            if let decoded { self.adoptIfNewer(decoded) }
            self.sendOfflineOutbox()
        }
    }

    /// Offers a workout on the wrist the moment the phone drops out of
    /// reach, and withdraws the offer when it comes back.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isPhoneReachable = reachable }
    }

    /// The phone's complication transfer: the same snapshot as its
    /// application context, sent so a suspended app is woken to refresh
    /// the complications.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = Self.decodeWatchData(from: userInfo) else { return }
        Task { @MainActor in self.adoptIfNewer(decoded) }
    }

    /// A failed transfer would otherwise be lost while the optimistic tap
    /// stays on the wrist. Re-queued once; the message id keeps a late
    /// duplicate from applying twice on the phone.
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil,
              userInfoTransfer.userInfo[Self.retriedKey] == nil,
              session.activationState == .activated else { return }
        session.transferUserInfo(userInfoTransfer.userInfo.merging([Self.retriedKey: true]) { _, retried in retried })
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
