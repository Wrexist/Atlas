import Foundation
import OSLog

/// App Group inbox of End fast taps from the fasting Live Activity,
/// drained by `FastingActivityActionProcessor`. The same hand-off the
/// workout and dose buttons use: the widget process can't reach
/// SwiftData, so it only records the tap and the app applies it.
enum PendingFastEndStore {
    struct Pending: Codable, Equatable, Sendable {
        let fastId: UUID
        /// When the user tapped — the fast's end time, however late the
        /// app gets to apply it.
        let endedAt: Date
    }

    private static let inboxKey = "com.peptidesai.app.pendingFastEnds"

    /// The app's drain, registered at launch. iOS runs the intent in the
    /// app's process and may suspend a background launch as soon as
    /// `perform()` returns, so the intent applies the tap through this
    /// before returning. Nil in the widget extension, where the inbox
    /// waits for the next foreground.
    @MainActor static var applyInProcess: (@MainActor () -> Void)?

    static func enqueue(_ pending: Pending, defaults: UserDefaults? = nil) {
        let store = defaults ?? sharedDefaults
        write(read(store) + [pending], to: store)
    }

    /// Every queued tap, oldest first; clears what it returns. A tap
    /// queued between the two reads stays for the next drain.
    static func drain(defaults: UserDefaults? = nil) -> [Pending] {
        let store = defaults ?? sharedDefaults
        let pending = read(store)
        guard !pending.isEmpty else { return [] }
        write(Array(read(store).dropFirst(pending.count)), to: store)
        return pending.sorted { $0.endedAt < $1.endedAt }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    /// Mirrors the app's subsystem directly, since `AppLog` isn't
    /// compiled into the widget extension.
    private static let log = Logger(subsystem: "com.peptidesai.app", category: "PendingFastEnd")

    private static func read(_ defaults: UserDefaults) -> [Pending] {
        guard let data = defaults.data(forKey: inboxKey) else { return [] }
        do {
            return try JSONDecoder().decode([Pending].self, from: data)
        } catch {
            log.error("inbox decode failed; dropping queued taps: \(error.localizedDescription, privacy: .public)")
            return []
        }
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

/// The End fast button on the fasting Live Activity. Ends the activity
/// on its summary beat straight away so the lock screen doesn't lag,
/// queues the tap, and — in the app's process — ends the fast itself
/// before returning.
@available(iOS 17.0, *)
struct EndFastLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End fast"
    static let isDiscoverable: Bool = false

    /// How long the "Fast ended" beat stays up before it dismisses.
    static let summarySeconds: TimeInterval = 4

    /// `@Parameter` doesn't bridge `UUID`, so the fast travels as a string.
    @Parameter(title: "Fast ID")
    var fastIdString: String

    init() {}

    init(fastId: UUID) {
        self.fastIdString = fastId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let fastId = UUID(uuidString: fastIdString) else { return .result() }
        let now = Date()
        PendingFastEndStore.enqueue(PendingFastEndStore.Pending(fastId: fastId, endedAt: now))

        if let activity = Activity<FastingActivityAttributes>.activities.first(where: {
            $0.attributes.fastId == fastId
        }), activity.content.state.endedAt == nil {
            var state = activity.content.state
            state.endedAt = now
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(now.addingTimeInterval(Self.summarySeconds))
            )
        }
        await MainActor.run { PendingFastEndStore.applyInProcess?() }
        return .result()
    }
}
#endif
