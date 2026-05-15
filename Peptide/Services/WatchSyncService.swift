import Foundation
import WatchConnectivity

/// Writes WatchData to the shared App Group container and handles
/// WCSession messaging between the iOS app and the Watch companion.
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    var onMarkComplete: ((UUID, UUID) -> Void)?
    var onMarkIncomplete: ((UUID, UUID) -> Void)?
    /// Callback fired when the watch logs water. Receives the
    /// ounces amount; the phone-side handler routes through
    /// `dataStore.logWater` so the widget reload + watch sync +
    /// HK write all fire for free.
    var onLogWater: ((Int) -> Void)?

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
        nutrition: WatchNutritionSnapshot? = nil
    ) {
        guard let url = watchDataURL else { return }

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
        .sorted { !$0.completed && $1.completed }

        let completed = watchEntries.filter(\.completed).count
        let data = WatchData(
            todayEntries: watchEntries,
            completedToday: completed,
            totalToday: watchEntries.count,
            lastUpdated: Date(),
            currentStreak: currentStreak,
            weeklyCompliance: weeklyCompliance,
            totalDosesLogged: totalDosesLogged,
            nutrition: nutrition
        )

        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: .atomic)
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
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(
                    ["watchData": dict],
                    replyHandler: nil,
                    errorHandler: { error in
                        AppLog.persistence.error("WatchSyncService: sendMessage failed, falling back to applicationContext: \(error.localizedDescription, privacy: .public)")
                        try? WCSession.default.updateApplicationContext(["watchData": dict])
                    }
                )
            } else {
                try? WCSession.default.updateApplicationContext(["watchData": dict])
            }
        } catch {
            AppLog.persistence.error("WatchSyncService: WCSession send failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }

        // Water-log path is its own shape — no entry/protocol IDs,
        // just the ounces. Branch early so the dose-related guard
        // below doesn't reject it.
        if action == WatchMessage.logWater {
            guard let oz = message[WatchMessage.ozKey] as? Int else { return }
            Task { [weak self] in
                await self?.handleWaterMessage(oz: oz)
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
            await self?.handleWatchMessage(action: action, entryId: entryId, protocolId: protocolId)
        }
    }
}

private extension WatchSyncService {
    func handleWaterMessage(oz: Int) {
        onLogWater?(oz)
    }

    func handleWatchMessage(action: String, entryId: UUID, protocolId: UUID) {
        switch action {
        case WatchMessage.markComplete:
            onMarkComplete?(entryId, protocolId)
        case WatchMessage.markIncomplete:
            onMarkIncomplete?(entryId, protocolId)
        default:
            break
        }
    }
}
