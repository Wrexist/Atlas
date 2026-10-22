import AppIntents
import Foundation
import Observation

/// The one-tap actions Atlas exposes outside the app — home-screen quick
/// actions, Control Center controls and widget buttons all speak this
/// vocabulary, and `peptidex://quick/<rawValue>` carries it as a link.
enum QuickAction: String, CaseIterable, Codable, Sendable {
    case scanMeal, logWater, startWorkout, logWeight

    var url: URL? { URL(string: "peptidex://quick/\(rawValue)") }

    var title: LocalizedStringResource {
        switch self {
        case .scanMeal:     "Scan meal"
        case .logWater:     "Log water"
        case .startWorkout: "Start workout"
        case .logWeight:    "Log weight"
        }
    }

    var systemImage: String {
        switch self {
        case .scanMeal:     "camera.viewfinder"
        case .logWater:     "drop.fill"
        case .startWorkout: "figure.strengthtraining.traditional"
        case .logWeight:    "scalemass.fill"
        }
    }
}

extension QuickAction: AppEnum {
    // Literals, not derived from `title`: the App Intents metadata
    // extractor reads these at build time and rejects computed values.
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quick action"
    static let caseDisplayRepresentations: [QuickAction: DisplayRepresentation] = [
        .scanMeal: "Scan meal",
        .logWater: "Log water",
        .startWorkout: "Start workout",
        .logWeight: "Log weight",
    ]
}

/// Hand-off point for quick actions that arrive without access to the
/// app's `AppState` — the home-screen shortcut scene delegate and the
/// open-app intent. `PeptideApp` watches `pending` and routes it.
@MainActor @Observable
final class QuickActionInbox {
    static let shared = QuickActionInbox()
    var pending: QuickAction?
}

/// Opens Atlas straight into one quick action. Backs the Control Center
/// controls; runs in the app process because it opens the app.
struct OpenQuickActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open quick action"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var action: QuickAction

    init() {}

    init(action: QuickAction) {
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.pending = action
        return .result()
    }
}

/// Logs one glass of water without opening the app — the Control Center
/// water control and the Nutrition widget's button. Runs in whichever
/// process taps it, so it only queues the glass; the app applies it.
struct LogWaterGlassIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a glass of water"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        PendingWaterLogStore.enqueue(Date())
        return .result()
    }
}

/// App Group inbox of water glasses tapped outside the app, drained by
/// `PendingWaterLogProcessor` — the same hand-off the dose Live Activity
/// uses (`PendingDoseLogStore`), since the widget process can't reach
/// SwiftData.
enum PendingWaterLogStore {
    private static let inboxKey = "com.peptidesai.app.pendingWaterGlasses"

    static func enqueue(_ loggedAt: Date, defaults: UserDefaults? = nil) {
        let store = defaults ?? sharedDefaults
        store.set(read(store) + [loggedAt], forKey: inboxKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(CrossProcessNotification.pendingWaterLogQueued as CFString),
            nil,
            nil,
            true
        )
    }

    /// Every queued tap time, oldest first; clears what it returns. A
    /// glass queued after the first read is the tail of the second one,
    /// so it stays for the next drain.
    static func drain(defaults: UserDefaults? = nil) -> [Date] {
        let store = defaults ?? sharedDefaults
        let pending = read(store)
        guard !pending.isEmpty else { return [] }
        let remainder = Array(read(store).dropFirst(pending.count))
        if remainder.isEmpty {
            store.removeObject(forKey: inboxKey)
        } else {
            store.set(remainder, forKey: inboxKey)
        }
        return pending.sorted()
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private static func read(_ defaults: UserDefaults) -> [Date] {
        defaults.array(forKey: inboxKey) as? [Date] ?? []
    }
}
