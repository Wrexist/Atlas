import ActivityKit
import Foundation

/// Live Activity controller for the in-progress workout — the training
/// counterpart to `DoseLiveActivityService`, and deliberately the same
/// shape: the app target owns it (`Activity.request` needs app
/// authorisation), every entry point bails early when Live Activities
/// are off or the OS is too old, and the dismiss path is token-guarded
/// so two `end()` calls can't race.
///
/// One workout runs at a time — `WorkoutSessionService` enforces that —
/// so this tracks a single activity rather than a dictionary.
@MainActor
final class WorkoutLiveActivityService {
    static let shared = WorkoutLiveActivityService()

    /// How long the "finished" summary stays up before the activity
    /// dismisses itself. Long enough to read the set count, short
    /// enough that it isn't litter on the lock screen.
    private static let summarySeconds: UInt64 = 4

    /// After this much silence the system greys the activity out. A
    /// workout nobody has touched in two hours is over in practice,
    /// whatever the app forgot to do.
    private static let stalenessHours: Int = 2

    /// In-flight "show the summary then end" task. Held so a discard,
    /// a new workout, or a repeat finish can cancel it instead of
    /// letting two `end()` calls race.
    private var dismissTask: Task<Void, Never>?

    /// Identity of the current dismiss task. Re-checked after the
    /// sleep, because past the sleep `cancel()` is a no-op and a
    /// superseding call would otherwise end the activity twice.
    private var dismissToken: UUID?

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
        cancelPendingDismiss()
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
        let existing = activity.content.state
        var next = Self.state(for: session)
        next.restEndsAt = existing.restEndsAt
        next.restTotalSeconds = existing.restTotalSeconds
        push(next, to: activity)
    }

    /// Mirrors `RestTimerState` onto the activity. Pass the state's own
    /// `targetEnd` — that absolute date is the single timing source for
    /// the overlay, the local notification, and now the lock screen.
    /// Nil ends the rest presentation.
    func updateRest(endsAt: Date?, totalSeconds: Double) {
        guard #available(iOS 16.1, *), let activity = currentActivity() else { return }
        var next = activity.content.state
        next.restEndsAt = endsAt
        next.restTotalSeconds = endsAt == nil ? 0 : totalSeconds
        push(next, to: activity)
    }

    /// Flips the activity into its summary beat, then dismisses it.
    func finish(_ session: WorkoutSession) {
        guard #available(iOS 16.1, *),
              let activity = currentActivity(for: session.id) else { return }
        var final = Self.state(for: session)
        final.restEndsAt = nil
        final.restTotalSeconds = 0
        final.finishedAt = session.finishedAt ?? Date()

        cancelPendingDismiss()
        let token = UUID()
        dismissToken = token
        dismissTask = Task { [weak self] in
            await activity.update(ActivityContent(state: final, staleDate: nil))
            do {
                try await Task.sleep(nanoseconds: Self.summarySeconds * 1_000_000_000)
            } catch {
                return // cancelled — a later call owns the activity now
            }
            guard await self?.dismissToken == token else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                self?.dismissTask = nil
                self?.dismissToken = nil
            }
        }
    }

    /// Ends every open workout activity immediately. Used on discard
    /// and on logout / data reset.
    func endAll() {
        guard #available(iOS 16.1, *) else { return }
        cancelPendingDismiss()
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

    private func cancelPendingDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        // Invalidate the token too: a task already past its sleep
        // ignores `cancel()`, and this is what stops it ending an
        // activity that now belongs to someone else.
        dismissToken = nil
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
            exerciseCount: session.exercises.count
        )
    }

    /// The exercise the user is working through: the first with an
    /// unchecked working set, falling back to the last one they touched
    /// so a finished-but-not-sealed workout doesn't blank the label.
    private static func currentExerciseName(in session: WorkoutSession) -> String {
        let ordered = session.exercises.sorted { $0.index < $1.index }
        let pending = ordered.first { entry in
            entry.sets.contains { !$0.completed && !$0.isWarmup }
        }
        guard let entry = pending ?? ordered.last else { return "" }
        return ExerciseLibrary.shared.lookup(id: entry.exerciseID)?.name ?? ""
    }
}
