import ActivityKit
import Foundation

/// Live Activity controller for the in-progress workout — the training
/// counterpart to `DoseLiveActivityService`, and deliberately the same
/// shape: the app target owns it (`Activity.request` needs app
/// authorisation), every entry point bails early when Live Activities
/// are off or the OS is too old, and the finished summary is handed to
/// the system to dismiss, so it clears even once the app is suspended.
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

    /// After this much silence the system greys the activity out. A
    /// workout nobody has touched in two hours is over in practice,
    /// whatever the app forgot to do.
    private static let stalenessHours: Int = 2

    private init() {}

    // MARK: - Public surface

    /// Brings open activities in line with `session`. Starts one for a
    /// workout that has none, ends any that belong to a workout that is
    /// over. Called on launch, where a session restored from disk would
    /// otherwise have lost its activity.
    func reconcile(active session: WorkoutSession?) {
        guard #available(iOS 16.1, *), areLiveActivitiesEnabled else { return }
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
        guard #available(iOS 16.1, *), areLiveActivitiesEnabled else { return }
        do {
            _ = try Activity<WorkoutActivityAttributes>.request(
                attributes: WorkoutActivityAttributes(
                    sessionId: session.id,
                    startedAt: session.startedAt
                ),
                content: ActivityContent(state: Self.state(for: session), staleDate: staleDate()),
                pushType: nil
            )
        } catch {
            // Authorisation revoked, system limit hit, etc. The next
            // reconcile tries again; a missing activity never blocks
            // the workout itself.
            AppLog.live.error("Workout Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pushes the session's current set / exercise counts. The rest
    /// countdown is carried over untouched — it isn't derived from the
    /// session, and a set being logged shouldn't reset it.
    func update(_ session: WorkoutSession) {
        guard #available(iOS 16.1, *),
              let activity = currentActivity(for: session.id) else { return }
        push(Self.state(for: session), to: activity)
    }

    /// Ends the activity on its summary beat. The system owns the
    /// dismissal, so it happens even if the phone is locked straight
    /// after Finish and the app is suspended.
    func finish(_ session: WorkoutSession) {
        guard #available(iOS 16.1, *),
              let activity = currentActivity(for: session.id) else { return }
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
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Internals

    @available(iOS 16.1, *)
    private var areLiveActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    @available(iOS 16.1, *)
    private func currentActivity(for sessionId: UUID? = nil) -> Activity<WorkoutActivityAttributes>? {
        let open = Activity<WorkoutActivityAttributes>.activities
        guard let sessionId else { return open.first }
        return open.first { $0.attributes.sessionId == sessionId }
    }

    @available(iOS 16.1, *)
    private func push(
        _ state: WorkoutActivityAttributes.ContentState,
        to activity: Activity<WorkoutActivityAttributes>
    ) {
        let content = ActivityContent(state: state, staleDate: staleDate())
        Task { await activity.update(content) }
    }

    private func staleDate() -> Date? {
        Calendar.current.date(byAdding: .hour, value: Self.stalenessHours, to: Date())
    }

    /// Pure mapping from a session to what the activity renders.
    /// Internal so the tests can pin it without ActivityKit running.
    @available(iOS 16.1, *)
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

    /// The exercise the user is working through: the first with an
    /// unchecked working set, falling back to the last one they touched
    /// so a finished-but-not-sealed workout doesn't blank the label.
    private static func currentExerciseName(in session: WorkoutSession) -> String {
        guard let entry = session.selectedExercise else { return "" }
        return ExerciseLibrary.shared.lookup(id: entry.exerciseID)?.name ?? entry.exerciseID
    }
}
