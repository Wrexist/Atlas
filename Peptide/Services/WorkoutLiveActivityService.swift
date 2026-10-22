import ActivityKit
import Foundation

/// Live Activity controller for the in-progress workout — the training
/// counterpart to `DoseLiveActivityService`, and deliberately the same
/// shape: the app target owns it (`Activity.request` needs app
/// authorisation), nothing new starts while Live Activities are off,
/// and the finished summary is handed to the system to dismiss, so it
/// clears even once the app is suspended.
///
/// One workout runs at a time — `WorkoutSessionService` enforces that —
/// so this tracks a single activity rather than a dictionary.
@MainActor
final class WorkoutLiveActivityService {
    static let shared = WorkoutLiveActivityService()

    /// How long the "finished" summary stays up before the activity
    /// dismisses itself. Long enough to read the set count, short
    /// enough that it isn't litter on the lock screen.
    private static let summarySeconds: TimeInterval = 4

    private init() {}

    // MARK: - Public surface

    /// Brings open activities in line with `session`. Starts one for a
    /// workout that has none, ends any that belong to a workout that is
    /// over — even with Live Activities switched off, so a card left up
    /// when the user disabled them still clears. Called on launch, where
    /// a session restored from disk would otherwise have lost its
    /// activity.
    func reconcile(active session: WorkoutSession?) {
        guard let session, session.isActive else {
            endAll()
            return
        }
        for activity in Activity<WorkoutActivityAttributes>.activities
        where activity.attributes.sessionId != session.id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        if currentActivity(for: session.id) == nil {
            start(session)
        } else {
            update(session)
        }
    }

    /// Requests an activity for a freshly started workout.
    func start(_ session: WorkoutSession) {
        guard areLiveActivitiesEnabled else { return }
        let state = Self.state(for: session)
        do {
            _ = try Activity<WorkoutActivityAttributes>.request(
                attributes: WorkoutActivityAttributes(
                    sessionId: session.id,
                    startedAt: session.startedAt
                ),
                content: ActivityContent(state: state, staleDate: state.staleDate()),
                pushType: nil
            )
        } catch {
            // Authorisation revoked, system limit hit, etc. The next
            // reconcile tries again; a missing activity never blocks
            // the workout itself.
            AppLog.live.error("Workout Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pushes the session's current set / exercise counts and its rest
    /// countdown, both read from the session (`focus.rest`), so logging a
    /// set leaves a running rest timer where it was.
    func update(_ session: WorkoutSession) {
        guard let activity = currentActivity(for: session.id) else { return }
        push(Self.state(for: session), to: activity)
    }

    /// Ends the activity on its summary beat. The system owns the
    /// dismissal, so it happens even if the phone is locked straight
    /// after Finish and the app is suspended.
    func finish(_ session: WorkoutSession) {
        guard let activity = currentActivity(for: session.id) else { return }
        var finalState = Self.state(for: session)
        finalState.restEndsAt = nil
        finalState.restTotalSeconds = 0
        finalState.finishedAt = session.finishedAt ?? Date()
        let dismissAt = Date().addingTimeInterval(Self.summarySeconds)
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(dismissAt)
            )
        }
    }

    /// Ends every open workout activity immediately. Used on discard
    /// and on logout / data reset.
    func endAll() {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Internals

    private var areLiveActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func currentActivity(for sessionId: UUID? = nil) -> Activity<WorkoutActivityAttributes>? {
        let open = Activity<WorkoutActivityAttributes>.activities
        guard let sessionId else { return open.first }
        return open.first { $0.attributes.sessionId == sessionId }
    }

    private func push(
        _ state: WorkoutActivityAttributes.ContentState,
        to activity: Activity<WorkoutActivityAttributes>
    ) {
        let content = ActivityContent(state: state, staleDate: state.staleDate())
        Task { await activity.update(content) }
    }

    /// Pure mapping from a session to what the activity renders.
    /// Internal so the tests can pin it without ActivityKit running.
    static func state(for session: WorkoutSession) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            workoutName: session.name ?? "",
            currentExercise: currentExerciseName(in: session),
            completedSets: session.completedSetCount,
            totalSets: session.exercises.reduce(0) { total, entry in
                total + entry.sets.filter { !$0.isWarmup }.count
            },
            exerciseCount: session.exercises.count,
            restEndsAt: session.isPaused ? nil : session.focus?.rest?.endsAt,
            restTotalSeconds: session.focus?.rest?.totalSeconds ?? 0,
            activeTimerStartedAt: session.startedAt.addingTimeInterval(session.focus?.pausedSeconds ?? 0),
            pausedElapsedSeconds: session.isPaused ? session.elapsedSeconds() : nil
        )
    }

    /// The exercise the user is working through: the one selected in the
    /// focus view, else the first with an unchecked set, else the first,
    /// so a finished-but-not-sealed workout doesn't blank the label.
    private static func currentExerciseName(in session: WorkoutSession) -> String {
        guard let entry = session.selectedExercise else { return "" }
        return ExerciseLibrary.shared.displayName(for: entry.exerciseID)
    }
}
