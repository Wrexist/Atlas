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

    /// A Complete set this soon after the last one on the same workout
    /// is a double tap on a button that hadn't caught up yet.
    static let doubleTapWindow: TimeInterval = 1.5

    /// Every queued tap, oldest first, minus double-tapped Complete
    /// sets; clears the inbox.
    static func drain(defaults: UserDefaults? = nil) -> [Pending] {
        let store = defaults ?? sharedDefaults
        let pending = read(store)
        if !pending.isEmpty { store.removeObject(forKey: inboxKey) }
        return withoutDoubleTaps(pending.sorted { $0.tappedAt < $1.tappedAt })
    }

    private static func withoutDoubleTaps(_ taps: [Pending]) -> [Pending] {
        var kept: [Pending] = []
        for tap in taps {
            let previous = kept.last { $0.sessionId == tap.sessionId && $0.action == .completeSet }
            if tap.action == .completeSet, let previous,
               tap.tappedAt.timeIntervalSince(previous.tappedAt) < doubleTapWindow {
                continue
            }
            kept.append(tap)
        }
        return kept
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
/// Activity. Queues the tap for the app, and applies it to the activity
/// straight away so the countdown or the set count doesn't lag until
/// the app catches up.
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

        if let activity = Activity<WorkoutActivityAttributes>.activities.first(where: {
            $0.attributes.sessionId == sessionId
        }) {
            var state = activity.content.state
            switch action {
            case .skipRest:
                state.restEndsAt = nil
                state.restTotalSeconds = 0
            case .completeSet:
                state.completedSets += 1
            }
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
        return .result()
    }
}
#endif
