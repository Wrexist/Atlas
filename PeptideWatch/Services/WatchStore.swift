import Foundation
import WatchConnectivity
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
        // stats fields (streak / weeklyCompliance / totalDosesLogged)
        // that arrived from the phone — the user just toggled a dose,
        // we shouldn't reset the streak to nil on every tap.
        if let index = watchData.todayEntries.firstIndex(where: { $0.id == entry.id }) {
            var updated = watchData.todayEntries
            updated[index].completed.toggle()
            let completed = updated.filter(\.completed).count
            watchData = WatchData(
                todayEntries: updated,
                completedToday: completed,
                totalToday: updated.count,
                lastUpdated: Date(),
                currentStreak: watchData.currentStreak,
                weeklyCompliance: watchData.weeklyCompliance,
                totalDosesLogged: watchData.totalDosesLogged
            )
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { [weak self] _ in
                Task { @MainActor in self?.isSending = false }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.isSending = false }
            })
        } else {
            isSending = false
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let dict = message["watchData"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(WatchData.self, from: data) else { return }
        Task { @MainActor in self.watchData = decoded }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let dict = context["watchData"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(WatchData.self, from: data) else { return }
        Task { @MainActor in self.watchData = decoded }
    }
}
