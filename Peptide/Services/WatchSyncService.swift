import Foundation
import WatchConnectivity

/// Writes WatchData to the shared App Group container and handles
/// WCSession messaging between the iOS app and the Watch companion.
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    var onMarkComplete: ((UUID, UUID) -> Void)?
    var onMarkIncomplete: ((UUID, UUID) -> Void)?

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

    func updateWatchData(entries: [ProtocolEntry], protocols: [PeptideProtocol]) {
        guard let url = watchDataURL else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: today) }

        let watchEntries = todayEntries.compactMap { entry -> WatchEntry? in
            guard protocols.contains(where: { $0.id == entry.protocolId }) else { return nil }
            let time = entry.actualTime.map {
                $0.formatted(.dateTime.hour().minute())
            } ?? entry.date.formatted(.dateTime.hour().minute())
            return WatchEntry(
                id: entry.id,
                protocolId: entry.protocolId,
                peptideName: entry.peptide.name,
                abbreviation: entry.peptide.abbreviation,
                dose: entry.actualDose ?? entry.dose,
                scheduledTime: time,
                completed: entry.completed
            )
        }
        .sorted { !$0.completed && $1.completed }

        let completed = watchEntries.filter(\.completed).count
        let data = WatchData(
            todayEntries: watchEntries,
            completedToday: completed,
            totalToday: watchEntries.count,
            lastUpdated: Date()
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
                WCSession.default.sendMessage(["watchData": dict], replyHandler: nil)
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
        guard let action = message["action"] as? String,
              let entryIdStr = message[WatchMessage.entryIdKey] as? String,
              let protocolIdStr = message[WatchMessage.protocolIdKey] as? String,
              let entryId = UUID(uuidString: entryIdStr),
              let protocolId = UUID(uuidString: protocolIdStr) else { return }

        Task { @MainActor in
            switch action {
            case WatchMessage.markComplete:
                self.onMarkComplete?(entryId, protocolId)
            case WatchMessage.markIncomplete:
                self.onMarkIncomplete?(entryId, protocolId)
            default:
                break
            }
        }
    }
}
