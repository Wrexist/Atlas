import ActivityKit
import Foundation

/// Live Activity controller for the fast in progress — the fasting
/// counterpart to `WorkoutLiveActivityService`, and the same shape: the
/// app target owns it, nothing new starts while Live Activities are off,
/// and the ended summary is handed to the system to dismiss.
///
/// `FastingStore` keeps at most one fast open, so this tracks a single
/// activity. It is driven entirely by `reconcile(active:sessions:)`, which the
/// store calls after every load and write, so a start, an end, a
/// cancelled fast and an edited start time all take one path.
@MainActor
final class FastingLiveActivityService {
    static let shared = FastingLiveActivityService()

    private init() {}

    /// Brings open activities in line with `fast`. Ends any that belong
    /// to a fast that is over — even with Live Activities off, so a card
    /// left up when the user disabled them still clears — then starts or
    /// updates one for the open fast. iOS ends a Live Activity after
    /// eight hours, shorter than most fasts, so the next reconcile (the
    /// app coming to the foreground) starts a fresh one and clears the
    /// frozen card iOS left behind. `sessions` is every fast the store
    /// knows, so an ended card shows when that fast really ended.
    func reconcile(active fast: FastSession?, sessions: [FastSession]) {
        for activity in openActivities where activity.attributes.fastId != fast?.id {
            end(activity, sessions: sessions)
        }
        guard let fast else { return }
        if let activity = openActivities.first(where: { $0.attributes.fastId == fast.id }) {
            let state = Self.state(for: fast)
            guard activity.content.state != state else { return }
            Task { await activity.update(ActivityContent(state: state, staleDate: state.staleDate())) }
        } else {
            dismissEndedCards(for: fast.id)
            start(fast)
        }
    }

    /// Ends every fasting activity immediately — on sign-out and data
    /// erase, where the fast it shows no longer exists.
    func endAll() {
        for activity in Activity<FastingActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Mapping

    /// Pure mapping from a fast to what the activity renders. Internal
    /// so tests can pin it without ActivityKit running.
    static func state(for fast: FastSession) -> FastingActivityAttributes.ContentState {
        FastingActivityAttributes.ContentState(
            startedAt: fast.startedAt,
            targetEnd: fast.targetEnd,
            endedAt: fast.endedAt
        )
    }

    /// "16:8", "OMAD", or the length of a custom fast ("20 h").
    static func protocolName(for fast: FastSession) -> String {
        guard fast.plan == .custom else { return fast.plan.title }
        return String(localized: "\(Int(fast.targetHours.rounded())) h", comment: "Custom fast length on the lock screen, e.g. 20 h")
    }

    /// How an open activity for a fast that is over leaves the screen.
    enum EndBeat: Equatable {
        /// The "Fast ended" summary, stamped with the fast's real end.
        case summary(endedAt: Date)
        /// Gone at once: the fast was deleted, or it ended a while ago
        /// on another device and a summary now would be old news.
        case dismiss
    }

    /// Pure, so tests can pin it without ActivityKit running.
    static func endBeat(for fastId: UUID, sessions: [FastSession], now: Date) -> EndBeat {
        guard let endedAt = sessions.first(where: { $0.id == fastId })?.endedAt,
              now.timeIntervalSince(endedAt) <= summaryFreshness else { return .dismiss }
        return .summary(endedAt: endedAt)
    }

    // MARK: - Internals

    /// How long the "Fast ended" beat stays up after an in-app end.
    private static let summarySeconds: TimeInterval = 4

    /// An end older than this arrived by sync, not from the user's hand
    /// just now, so it gets no summary beat.
    private static let summaryFreshness: TimeInterval = 60

    /// Activities the system hasn't ended yet. One iOS ended after eight
    /// hours lingers in `activities` until dismissed, and must not stop
    /// a fresh one from starting.
    private var openActivities: [Activity<FastingActivityAttributes>] {
        Activity<FastingActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private func start(_ fast: FastSession) {
        guard fast.isActive, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.state(for: fast)
        do {
            _ = try Activity<FastingActivityAttributes>.request(
                attributes: FastingActivityAttributes(fastId: fast.id, protocolName: Self.protocolName(for: fast)),
                content: ActivityContent(state: state, staleDate: state.staleDate()),
                pushType: nil
            )
        } catch {
            // A missing activity never blocks the fast; the next
            // reconcile tries again.
            AppLog.live.error("Fasting Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ends on the summary beat, which the system dismisses on its own
    /// even once the app is suspended, or at once for a deleted fast or
    /// one that ended elsewhere a while ago.
    private func end(_ activity: Activity<FastingActivityAttributes>, sessions: [FastSession]) {
        let now = Date()
        switch Self.endBeat(for: activity.attributes.fastId, sessions: sessions, now: now) {
        case .summary(let endedAt):
            var state = activity.content.state
            state.endedAt = endedAt
            let dismissAt = now.addingTimeInterval(Self.summarySeconds)
            Task {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(dismissAt))
            }
        case .dismiss:
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// A card iOS ended at its eight-hour limit stays on the Lock Screen
    /// for hours; clear it before a fresh one starts beside it. Only this
    /// fast's, so another fast's summary beat plays out.
    private func dismissEndedCards(for fastId: UUID) {
        for stale in Activity<FastingActivityAttributes>.activities
        where stale.activityState == .ended && stale.attributes.fastId == fastId {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
