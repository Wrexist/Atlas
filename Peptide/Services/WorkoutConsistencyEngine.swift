import Foundation

/// Builds the "you're building consistency" line shown on
/// `WorkoutFinishView` — the single highest-motivation moment in the
/// training loop, and, before this pass, one where Atlas showed PRs but
/// never the session's place in the user's weekly rhythm even though that
/// count was already being computed elsewhere for the Train tab's heatmap.
///
/// Pure function over a session count — no I/O — so the caller decides how
/// "this week" is windowed (see `ActiveWorkoutView`, which counts sessions
/// via `SwiftDataRepository.loadWorkoutSessions(startedBetween:)`) and this
/// just turns a count into honest copy.
enum WorkoutConsistencyEngine {

    /// Returns `nil` for a first session this week — "1st workout this
    /// week" isn't a consistency signal yet, it's just "you worked out."
    /// The callout only appears once there's an actual pattern to name.
    static func callout(sessionsInTrailingWeek count: Int) -> String? {
        guard count >= 2 else { return nil }
        let ordinal = Self.ordinalFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(ordinal) workout this week — you're building consistency."
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}
