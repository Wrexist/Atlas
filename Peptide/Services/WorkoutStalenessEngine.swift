import Foundation

/// Decides what to do with an in-progress workout nobody has touched in
/// hours — the session left open overnight that otherwise greets the user
/// with a 208-hour timer. Pure: the service applies the verdict.
enum WorkoutStalenessEngine {
    enum Verdict: Equatable {
        case keep
        /// Nothing worth saving — no completed working set.
        case discard
        /// Seal the workout at this instant, so its history row and
        /// duration reflect when the user actually stopped lifting.
        case finish(at: Date)
    }

    /// An empty session is abandoned sooner: there is nothing to lose.
    static let emptyIdleLimit: TimeInterval = 4 * 3600
    static let loggedIdleLimit: TimeInterval = 6 * 3600
    /// Time credited after the last logged set — the final rest and
    /// re-rack the user did before walking away.
    static let finishBuffer: TimeInterval = 60

    /// The latest moment the session shows the user doing something. Only
    /// set completion is timestamped (`SetEntry.completedAt`), so weight /
    /// rep edits and added exercises are invisible here; a pause counts
    /// because it is an explicit tap. Completed sets from before
    /// `completedAt` existed carry no time and fall back to `startedAt`.
    static func lastActivity(of session: WorkoutSession) -> Date {
        let setTimes = session.exercises.flatMap(\.sets).compactMap(\.completedAt)
        let candidates = setTimes + [session.startedAt, session.focus?.pausedAt].compactMap { $0 }
        return candidates.max() ?? session.startedAt
    }

    static func verdict(for session: WorkoutSession, now: Date) -> Verdict {
        guard session.isActive else { return .keep }
        let last = lastActivity(of: session)
        let idle = now.timeIntervalSince(last)
        guard session.completedSetCount > 0 else {
            return idle > emptyIdleLimit ? .discard : .keep
        }
        guard idle > loggedIdleLimit else { return .keep }
        return .finish(at: min(last.addingTimeInterval(finishBuffer), now))
    }
}
