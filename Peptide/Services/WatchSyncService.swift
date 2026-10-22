import Foundation
@preconcurrency import WatchConnectivity

/// Writes WatchData to the shared App Group container and handles
/// WCSession messaging between the iOS app and the Watch companion.
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    /// Receives the entry, its protocol and when the user tapped.
    var onMarkComplete: ((UUID, UUID, Date) -> Void)?
    var onMarkIncomplete: ((UUID, UUID) -> Void)?
    /// Callback fired when the watch logs water. Receives the exact
    /// fluid-ounce amount and when the user tapped; the phone-side
    /// handler routes through `dataStore.logWater` so the widget reload
    /// + watch sync + HK write all fire for free.
    var onLogWater: ((Double, Date) -> Void)?

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

    /// Vitals from the last snapshot this phone wrote. Lets `DataStore`
    /// carry them across a relaunch: until its first HealthKit refresh
    /// lands, every push would otherwise send nil and the Watch would
    /// drop its Recovery and Sleep pages.
    nonisolated static func lastWrittenVitals() -> WatchVitalsSnapshot? {
        readLastWritten()?.vitals
    }

    nonisolated private static func readLastWritten() -> WatchData? {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchData.self, from: data)
    }

    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func updateWatchData(
        entries: [ProtocolEntry],
        protocols: [PeptideProtocol],
        currentStreak: Int? = nil,
        weeklyCompliance: Double? = nil,
        totalDosesLogged: Int? = nil,
        nutrition: WatchNutritionSnapshot? = nil,
        atlasScore: Int? = nil,
        atlasLevel: Int? = nil,
        atlasTier: String? = nil,
        atlasProgress: Double? = nil,
        atlasTodayEarned: Int? = nil,
        healthHabitsDone: Int? = nil,
        healthHabitsTotal: Int? = nil,
        trainingHabitsDone: Int? = nil,
        trainingHabitsTotal: Int? = nil,
        measurementUnit: String? = nil,
        healthConnected: Bool? = nil,
        vitals: WatchVitalsSnapshot? = nil,
        workout: WatchWorkoutSnapshot? = nil,
        training: WatchTrainingSnapshot? = nil,
        hapticsEnabled: Bool? = nil
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: today) }

        let watchEntries = todayEntries.compactMap { entry -> WatchEntry? in
            guard protocols.contains(where: { $0.id == entry.protocolId }) else { return nil }
            return WatchEntry(
                id: entry.id,
                protocolId: entry.protocolId,
                peptideName: entry.peptide.name,
                abbreviation: entry.peptide.abbreviation,
                dose: entry.actualDose ?? entry.dose,
                scheduledTime: entry.actualTime ?? entry.date,
                completed: entry.completed
            )
        }
        // Strict-weak-ordering comparator: incomplete doses first,
        // then by scheduled time within each group. The old
        // `!$0.completed && $1.completed` predicate isn't a valid
        // ordering and left same-group entries in arbitrary order.
        .sorted { lhs, rhs in
            lhs.completed == rhs.completed
                ? lhs.scheduledTime < rhs.scheduledTime
                : !lhs.completed
        }

        let completed = watchEntries.filter(\.completed).count
        let data = WatchData(
            todayEntries: watchEntries,
            completedToday: completed,
            totalToday: watchEntries.count,
            lastUpdated: Date(),
            currentStreak: currentStreak,
            weeklyCompliance: weeklyCompliance,
            totalDosesLogged: totalDosesLogged,
            nutrition: nutrition,
            atlasScore: atlasScore,
            atlasLevel: atlasLevel,
            atlasTier: atlasTier,
            atlasProgress: atlasProgress,
            atlasTodayEarned: atlasTodayEarned,
            healthHabitsDone: healthHabitsDone,
            healthHabitsTotal: healthHabitsTotal,
            trainingHabitsDone: trainingHabitsDone,
            trainingHabitsTotal: trainingHabitsTotal,
            measurementUnit: measurementUnit,
            healthConnected: healthConnected,
            vitals: vitals,
            workout: workout,
            training: training,
            hapticsEnabled: hapticsEnabled
        )
        publish(data)
    }

    /// Re-sends the last snapshot with a new workout state. Set edits
    /// arrive many times a minute mid-workout; rebuilding the whole
    /// snapshot for each would redo the dose, habit and score math.
    /// Stamped with the push time so the Watch can tell it from an older
    /// push; a snapshot from an earlier day drops that day's progress
    /// first, so the new stamp doesn't pass yesterday's doses off as today's.
    func updateWorkout(_ workout: WatchWorkoutSnapshot?) {
        guard let last = lastPublished ?? Self.readLastWritten(),
              last.workout != workout else { return }
        let now = Date()
        publish(last.forDisplay(at: now).replacingWorkout(workout, updatedAt: now))
    }

    /// Re-sends the latest snapshot. A push made before the session
    /// finished activating, or before the Watch app was installed, was
    /// dropped, and nothing else would send it again until the next edit.
    private func resendLatest() {
        guard let latest = lastPublished ?? Self.readLastWritten() else { return }
        sendWatchDataIfReachable(latest)
    }

    /// The snapshot most recently written, so `updateWorkout` can carry
    /// the other fields forward.
    private var lastPublished: WatchData?

    private func publish(_ data: WatchData) {
        lastPublished = data
        guard let url = watchDataURL else { return }
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: .atomic)
            // Regenerated-cache file — exclude from iCloud Backup
            // so it doesn't waste user quota / inflate restore time.
            PersistenceService.excludeFromBackup(url)
        } catch {
            AppLog.persistence.error("WatchSyncService: failed to write WatchData: \(error.localizedDescription, privacy: .public)")
        }

        sendWatchDataIfReachable(data)
    }

    private func sendWatchDataIfReachable(_ data: WatchData) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }

        do {
            let encoded = try encoder.encode(data)
            guard let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }
            // Always use `updateApplicationContext` for bulk-state push.
            //
            // `sendMessage` is for imperative commands that need an ack.
            // Bursty mutations (three dose toggles in 350 ms) used to
            // queue three independent messages with no ordering
            // guarantee — the Watch could process them out of order
            // and surface a stale completion count.
            // `updateApplicationContext` is last-write-wins by design
            // and the system coalesces redundant updates, which is
            // exactly the right semantics for "here's the current
            // snapshot."
            try WCSession.default.updateApplicationContext(["watchData": dict])
        } catch {
            AppLog.persistence.error("WatchSyncService: WCSession send failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { [weak self] in await self?.resendLatest() }
    }

    /// Fires when the Watch app is installed or removed (among other
    /// pairing changes), so a newly installed app gets a snapshot at once.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { [weak self] in await self?.resendLatest() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // The Watch falls back to `transferUserInfo` when the phone is
        // unreachable at tap time. Same payload shape as a live
        // message, so route it through the identical handler.
        // `self.` is required — the `session` parameter shadows the
        // method name in local lookup.
        self.session(session, didReceiveMessage: userInfo)
    }

    /// The Watch sends with a reply handler so it can clear its in-flight
    /// state on delivery. Without this variant WCSession reports every
    /// live send as failed and the Watch drops to the slower
    /// `transferUserInfo` path. The reply is an ack only; the new state
    /// arrives through the next application-context push.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        self.session(session, didReceiveMessage: message)
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        let messageID = message[WatchMessage.messageIdKey] as? String
        let issuedAt = (message[WatchMessage.issuedAtKey] as? Double).map { Date(timeIntervalSince1970: $0) }

        // Workout and water commands are their own shapes, with no
        // entry/protocol IDs. Branch early so the dose-related guard
        // below doesn't reject them.
        if action == WatchMessage.workout {
            guard let payload = message[WatchMessage.workoutRequestKey] as? Data,
                  let request = WatchWorkoutRequest.decode(payload) else { return }
            Task { [weak self] in
                await self?.handleWorkoutRequest(request, messageID: messageID)
            }
            return
        }

        if action == WatchMessage.logWater {
            // Older Watch builds send whole ounces only.
            guard let fluidOunces = message[WatchMessage.fluidOuncesKey] as? Double
                    ?? (message[WatchMessage.ozKey] as? Int).map(Double.init) else { return }
            Task { [weak self] in
                await self?.handleWaterMessage(fluidOunces: fluidOunces, issuedAt: issuedAt, messageID: messageID)
            }
            return
        }

        guard let entryIdStr = message[WatchMessage.entryIdKey] as? String,
              let protocolIdStr = message[WatchMessage.protocolIdKey] as? String,
              let entryId = UUID(uuidString: entryIdStr),
              let protocolId = UUID(uuidString: protocolIdStr) else { return }

        // The delegate is nonisolated (required by WCSessionDelegate)
        // but `onMarkComplete` / `onMarkIncomplete` are mutable @MainActor
        // properties. Hand off to a @MainActor method so the closure
        // reads happen on main — keeps Swift 6 strict-concurrency happy
        // and removes any race with a parent reassigning the callbacks.
        Task { [weak self] in
            await self?.handleWatchMessage(
                action: action, entryId: entryId, protocolId: protocolId, issuedAt: issuedAt, messageID: messageID
            )
        }
    }
}

private extension WatchSyncService {
    static let handledMessageIDsKey = "watchSync.handledMessageIDs"
    static let handledMessageIDsLimit = 50

    /// Records a Watch command's id and reports whether this is its first
    /// delivery. Kept across launches because the `transferUserInfo`
    /// duplicate can land long after the live send. Commands from an older
    /// Watch build carry no id and always pass.
    func isFirstDelivery(_ messageID: String?) -> Bool {
        guard let messageID else { return true }
        let defaults = UserDefaults.standard
        var handled = defaults.stringArray(forKey: Self.handledMessageIDsKey) ?? []
        guard !handled.contains(messageID) else { return false }
        handled.append(messageID)
        defaults.set(Array(handled.suffix(Self.handledMessageIDsLimit)), forKey: Self.handledMessageIDsKey)
        return true
    }

    func handleWorkoutRequest(_ request: WatchWorkoutRequest, messageID: String?) {
        guard isFirstDelivery(messageID) else { return }
        WorkoutSessionService.shared.apply(request)
    }

    /// Logged at the tap, never in the future: a water tap queued while the
    /// phone was away still lands on the day it was made.
    func handleWaterMessage(fluidOunces: Double, issuedAt: Date?, messageID: String?) {
        guard isFirstDelivery(messageID) else { return }
        let now = Date()
        onLogWater?(fluidOunces, min(issuedAt ?? now, now))
    }

    /// A dose tapped while the phone was away is stamped with the tap
    /// time, not the delivery time.
    func handleWatchMessage(action: String, entryId: UUID, protocolId: UUID, issuedAt: Date?, messageID: String?) {
        guard isFirstDelivery(messageID) else { return }
        switch action {
        case WatchMessage.markComplete:
            let now = Date()
            onMarkComplete?(entryId, protocolId, min(issuedAt ?? now, now))
        case WatchMessage.markIncomplete:
            onMarkIncomplete?(entryId, protocolId)
        default:
            break
        }
    }
}
