import Foundation

/// What the workout Live Activity's button can ask for: end the rest
/// early, or tick off the set the user just did.
enum WorkoutActivityAction: String, Codable, Sendable {
    case skipRest, completeSet
}

/// App Group inbox of workout Live Activity taps, drained by
/// `WorkoutActivityActionProcessor`. The same hand-off the dose and
/// water buttons use: the widget process can't reach SwiftData, so it
/// only records the tap and the app applies it.
enum PendingWorkoutActionStore {
    struct Pending: Codable, Equatable, Sendable {
        let sessionId: UUID
        let action: WorkoutActivityAction
        let tappedAt: Date
    }

    private static let inboxKey = "com.peptidesai.app.pendingWorkoutActions"

    static func enqueue(_ pending: Pending, defaults: UserDefaults? = nil) {
        let store = defaults ?? sharedDefaults
        guard let data = try? JSONEncoder().encode(read(store) + [pending]) else { return }
        store.set(data, forKey: inboxKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(CrossProcessNotification.pendingWorkoutActionQueued as CFString),
            nil,
            nil,
            true
        )
    }

    /// Every queued tap, oldest first; clears the inbox.
    static func drain(defaults: UserDefaults? = nil) -> [Pending] {
        let store = defaults ?? sharedDefaults
        let pending = read(store)
        if !pending.isEmpty { store.removeObject(forKey: inboxKey) }
        return pending.sorted { $0.tappedAt < $1.tappedAt }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private static func read(_ defaults: UserDefaults) -> [Pending] {
        guard let data = defaults.data(forKey: inboxKey) else { return [] }
        return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
    }
}

#if canImport(ActivityKit) && canImport(AppIntents)
import ActivityKit
import AppIntents

/// The "Skip rest" / "Complete set" button on the workout Live
/// Activity. Queues the tap for the app, and ends a skipped rest on the
/// activity straight away so the countdown doesn't linger until the app
/// catches up.
@available(iOS 17.0, *)
struct WorkoutActivityActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Workout action"
    static let isDiscoverable: Bool = false

    /// `@Parameter` doesn't bridge `UUID`, so the session travels as a string.
    @Parameter(title: "Session ID")
    var sessionIdString: String

    @Parameter(title: "Action")
    var actionRawValue: String

    init() {}

    init(sessionId: UUID, action: WorkoutActivityAction) {
        self.sessionIdString = sessionId.uuidString
        self.actionRawValue = action.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let sessionId = UUID(uuidString: sessionIdString),
              let action = WorkoutActivityAction(rawValue: actionRawValue) else {
            return .result()
        }
        PendingWorkoutActionStore.enqueue(.init(sessionId: sessionId, action: action, tappedAt: Date()))

        if action == .skipRest,
           let activity = Activity<WorkoutActivityAttributes>.activities.first(where: {
               $0.attributes.sessionId == sessionId
           }) {
            var state = activity.content.state
            state.restEndsAt = nil
            state.restTotalSeconds = 0
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
        return .result()
    }
}
#endif
