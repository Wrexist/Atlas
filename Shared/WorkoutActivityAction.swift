import Foundation
import OSLog

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
    /// The last Complete set queued. `drain` never clears it, so a
    /// double tap still matches after the app has drained the first.
    private static let lastCompleteSetKey = "com.peptidesai.app.lastWorkoutCompleteSet"

    static func enqueue(_ pending: Pending, defaults: UserDefaults? = nil) {
        let store = defaults ?? sharedDefaults
        write(read(store) + [pending], to: store)
        if pending.action == .completeSet {
            writeLastCompleteSet(pending, to: store)
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(CrossProcessNotification.pendingWorkoutActionQueued as CFString),
            nil,
            nil,
            true
        )
    }

    /// The app's drain, registered at launch. iOS runs the Live Activity
    /// intent in the app's process and may suspend a background launch
    /// as soon as `perform()` returns, before the Darwin-notification
    /// drain gets its turn, so the intent applies the tap through this
    /// first. Nil in the widget extension, where the inbox is the path.
    @MainActor static var applyInProcess: (@MainActor () -> Void)?

    /// A Complete set this soon after the last one on the same workout
    /// is a double tap on a button that hadn't caught up yet.
    static let doubleTapWindow: TimeInterval = 1.5

    /// Every queued tap, oldest first, minus double-tapped Complete
    /// sets; clears what it returns. Taps only ever append, so a tap the
    /// widget queued after the first read is the tail of the second one,
    /// and stays for the next drain rather than being wiped unseen.
    static func drain(defaults: UserDefaults? = nil) -> [Pending] {
        let store = defaults ?? sharedDefaults
        let pending = read(store)
        guard !pending.isEmpty else { return [] }
        write(Array(read(store).dropFirst(pending.count)), to: store)
        return withoutDoubleTaps(pending.sorted { $0.tappedAt < $1.tappedAt })
    }

    /// Whether `tap` doubles the last Complete set queued, drained or
    /// not. The button checks before queuing, so a double tap neither
    /// logs nor shows a second set; `drain` repeats the check within a
    /// batch as a backstop.
    static func isDoubleTap(_ tap: Pending, defaults: UserDefaults? = nil) -> Bool {
        let store = defaults ?? sharedDefaults
        return isDoubleTap(tap, after: [readLastCompleteSet(store)].compactMap { $0 } + read(store))
    }

    private static func isDoubleTap(_ tap: Pending, after earlier: [Pending]) -> Bool {
        guard tap.action == .completeSet,
              let previous = earlier.last(where: { $0.sessionId == tap.sessionId && $0.action == .completeSet })
        else { return false }
        return tap.tappedAt.timeIntervalSince(previous.tappedAt) < doubleTapWindow
    }

    private static func withoutDoubleTaps(_ taps: [Pending]) -> [Pending] {
        var kept: [Pending] = []
        for tap in taps where !isDoubleTap(tap, after: kept) {
            kept.append(tap)
        }
        return kept
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    /// Mirrors the app's subsystem directly, since `AppLog` isn't
    /// compiled into the widget extension.
    private static let log = Logger(subsystem: "com.peptidesai.app", category: "PendingWorkoutAction")

    private static func read(_ defaults: UserDefaults) -> [Pending] {
        guard let data = defaults.data(forKey: inboxKey) else { return [] }
        do {
            return try JSONDecoder().decode([Pending].self, from: data)
        } catch {
            log.error("inbox decode failed; dropping queued taps: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func readLastCompleteSet(_ defaults: UserDefaults) -> Pending? {
        guard let data = defaults.data(forKey: lastCompleteSetKey) else { return nil }
        return try? JSONDecoder().decode(Pending.self, from: data)
    }

    private static func writeLastCompleteSet(_ tap: Pending, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(tap) else { return }
        defaults.set(data, forKey: lastCompleteSetKey)
    }

    private static func write(_ taps: [Pending], to defaults: UserDefaults) {
        guard !taps.isEmpty else {
            defaults.removeObject(forKey: inboxKey)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(taps), forKey: inboxKey)
        } catch {
            log.error("inbox encode failed; tap not queued: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if canImport(ActivityKit) && canImport(AppIntents)
import ActivityKit
import AppIntents

/// The "Skip rest" / "Complete set" button on the workout Live
/// Activity. Applies it to the activity straight away so the countdown
/// or the set count doesn't lag, queues the tap, and — in the app's
/// process — applies it to the workout before returning.
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
        let tap = PendingWorkoutActionStore.Pending(sessionId: sessionId, action: action, tappedAt: Date())
        guard !PendingWorkoutActionStore.isDoubleTap(tap) else { return .result() }

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
            await activity.update(ActivityContent(state: state, staleDate: state.staleDate()))
        }
        // Queued after the update: the app's push of the real count
        // must land on top of this one, not be read back and bumped.
        PendingWorkoutActionStore.enqueue(tap)
        await MainActor.run { PendingWorkoutActionStore.applyInProcess?() }
        return .result()
    }
}
#endif
