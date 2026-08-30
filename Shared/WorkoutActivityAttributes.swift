import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// ActivityAttributes for the in-progress workout. Lives in /Shared so
/// the app target (which starts and updates the activity) and the
/// widget extension (which renders it) see the same struct — the same
/// arrangement `DoseWindowAttributes` uses.
///
/// Only `sessionId` and `startedAt` are static for the life of a
/// workout, so everything else — the name (the user can rename
/// mid-session), the set counts, the rest countdown — lives in
/// `ContentState` where an update can reach it.
///
/// The rest timer is folded into this activity rather than given its
/// own. It is the same event from the user's side ("I'm between sets
/// of this workout"), and `RestTimerState` already owns the absolute
/// target date plus the local notification — a second activity would
/// mean a second source of truth for one countdown.
@available(iOS 16.1, *)
struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias WorkoutStatus = ContentState

    public struct ContentState: Codable, Hashable {
        /// Display name, or "" for an unnamed workout — the widget
        /// falls back to "Workout" rather than rendering a blank line.
        public var workoutName: String
        /// Name of the exercise the user is on, or "" before they add
        /// one. Pre-resolved app-side so the widget needs no library.
        public var currentExercise: String
        /// Completed working sets over planned sets.
        public var completedSets: Int
        public var totalSets: Int
        public var exerciseCount: Int
        /// Absolute moment the current rest ends, or nil while lifting.
        /// Sourced from `RestTimerState.targetEnd` — the widget renders
        /// `Text(timerInterval:)` against it without per-second pushes.
        public var restEndsAt: Date?
        /// Length of the current rest, for the countdown ring. Zero
        /// while not resting.
        public var restTotalSeconds: Double
        /// Set on finish. Flips the activity into a short summary beat
        /// before `WorkoutLiveActivityService` dismisses it.
        public var finishedAt: Date?

        public init(
            workoutName: String,
            currentExercise: String = "",
            completedSets: Int = 0,
            totalSets: Int = 0,
            exerciseCount: Int = 0,
            restEndsAt: Date? = nil,
            restTotalSeconds: Double = 0,
            finishedAt: Date? = nil
        ) {
            self.workoutName = workoutName
            self.currentExercise = currentExercise
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.exerciseCount = exerciseCount
            self.restEndsAt = restEndsAt
            self.restTotalSeconds = restTotalSeconds
            self.finishedAt = finishedAt
        }
    }

    /// Identifies the originating `WorkoutSession` so the service can
    /// match an open activity back to the session it belongs to, and
    /// the deep-link handler can route a tap.
    public let sessionId: UUID
    /// Wall-clock start. Fixed for the activity's life, which is what
    /// lets the widget count elapsed time with no pushes at all.
    public let startedAt: Date

    public init(sessionId: UUID, startedAt: Date) {
        self.sessionId = sessionId
        self.startedAt = startedAt
    }
}

// MARK: - Status state machine

@available(iOS 16.1, *)
extension WorkoutActivityAttributes.ContentState {

    /// What the widget renders. Derived from `restEndsAt`, `finishedAt`
    /// and the wall clock, so the lock screen and the expanded Dynamic
    /// Island read one enum instead of duplicating the thresholds.
    ///
    /// Access level: internal, for the reason spelled out on
    /// `DoseWindowAttributes.ContentState.Status` — /Shared compiles
    /// into both modules, so `public` would be vestigial.
    enum Status: Equatable {
        /// Mid-set. The activity shows elapsed workout time.
        case lifting
        /// Between sets. Carries whole seconds left so the widget
        /// doesn't redo the arithmetic.
        case resting(secondsRemaining: Int)
        /// Terminal. The service dismisses shortly after.
        case finished
    }

    /// Pure: the same inputs always give the same answer, so the widget
    /// renders deterministically and the state machine is testable
    /// without ActivityKit in the loop.
    func status(at now: Date = Date()) -> Status {
        if finishedAt != nil { return .finished }
        guard let restEndsAt, restEndsAt > now else { return .lifting }
        return .resting(secondsRemaining: Int(restEndsAt.timeIntervalSince(now).rounded(.up)))
    }

    /// 0…1 through the current rest. Zero when not resting, so the ring
    /// has nothing to draw rather than a stale arc.
    func restProgress(at now: Date = Date()) -> Double {
        guard restTotalSeconds > 0, let restEndsAt, restEndsAt > now else { return 0 }
        let elapsed = restTotalSeconds - restEndsAt.timeIntervalSince(now)
        return min(max(elapsed / restTotalSeconds, 0), 1)
    }

    /// 0…1 through the planned sets. Clamped so an extra set logged
    /// beyond the plan doesn't overdraw the bar.
    var setProgress: Double {
        guard totalSets > 0 else { return 0 }
        return min(max(Double(completedSets) / Double(totalSets), 0), 1)
    }

    /// What to print as the title. Kept here so the lock screen, the
    /// compact pill and the expanded island can't disagree.
    var displayName: String {
        workoutName.isEmpty ? "Workout" : workoutName
    }
}
#endif
