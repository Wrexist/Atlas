import Foundation

/// How far through its planned working sets a live workout is, and what
/// the focus screen says about it. Warm-ups never count, matching the
/// set totals on the recap, history and Live Activity.
enum WorkoutProgressEngine {
    /// One exercise's share of the session bar.
    struct Segment: Equatable, Identifiable {
        let id: UUID
        let done: Int
        let total: Int
    }

    struct Progress: Equatable {
        let segments: [Segment]

        var done: Int { segments.reduce(0) { $0 + $1.done } }
        var total: Int { segments.reduce(0) { $0 + $1.total } }
        var remaining: Int { max(0, total - done) }
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
        /// Rounded down, so 100 % only ever means every set is in.
        var percent: Int { Int((fraction * 100).rounded(.down)) }
    }

    /// What the header says between sets.
    enum Status: Equatable {
        case start
        case setsToGo(Int)
        case pastHalfway(Int)
        case almostThere(Int)
        case lastSet
        case allDone
    }

    /// A completed set measured against the same set last session.
    enum Gain: Equatable {
        case weight(kg: Double)
        case reps(Int)
        case matched
    }

    /// The brief line that answers a checked set.
    enum Reward: Equatable {
        case exerciseDone
        case gain(Gain)
        case milestone(Int)
        case set(variant: Int)
    }

    /// Percentages that earn their own beat as the bar crosses them.
    /// 100 % is the exercise-done and finish moment, which has its own.
    static let milestones = [25, 50, 75]

    static func progress(of session: WorkoutSession) -> Progress {
        Progress(segments: session.exercises.compactMap { entry in
            let working = entry.sets.filter { !$0.isWarmup }
            guard !working.isEmpty else { return nil }
            return Segment(id: entry.id, done: working.filter(\.completed).count, total: working.count)
        })
    }

    static func status(for progress: Progress) -> Status {
        guard progress.total > 0, progress.done > 0 else { return .start }
        switch progress.remaining {
        case 0: return .allDone
        case 1: return .lastSet
        case 2...3: return .almostThere(progress.remaining)
        default:
            return progress.percent >= 50 ? .pastHalfway(progress.remaining) : .setsToGo(progress.remaining)
        }
    }

    /// The highest milestone passed going up from `old` to `new` percent.
    static func milestone(from old: Int, to new: Int) -> Int? {
        milestones.last { old < $0 && new >= $0 }
    }

    /// Nil when the set fell short of last time, or there is nothing to
    /// compare: a shortfall isn't worth announcing mid-workout.
    static func gain(_ set: SetEntry, over previous: SetEntry?) -> Gain? {
        guard let previous, set.supportsRepLogging, previous.supportsRepLogging,
              set.reps > 0, previous.reps > 0 else { return nil }
        let weightDelta = set.weightKg - previous.weightKg
        let tolerance = 0.01
        if weightDelta > tolerance, set.reps >= previous.reps { return .weight(kg: weightDelta) }
        if abs(weightDelta) <= tolerance {
            if set.reps > previous.reps { return .reps(set.reps - previous.reps) }
            if set.reps == previous.reps { return .matched }
        }
        return nil
    }

    /// The working set checked between two snapshots of the same session.
    /// Nil for an uncheck, an edit, or more than one set changing at once
    /// (a restore or a Watch sync), none of which the lifter just did.
    static func newlyCompleted(before: WorkoutSession, after: WorkoutSession) -> (entry: WorkoutExerciseEntry, set: SetEntry)? {
        guard before.id == after.id else { return nil }
        let wasDone = Set(before.exercises.flatMap(\.completedWorkingSets).map(\.id))
        let fresh = after.exercises.flatMap { entry in
            entry.completedWorkingSets.filter { !wasDone.contains($0.id) }.map { (entry: entry, set: $0) }
        }
        return fresh.count == 1 ? fresh[0] : nil
    }

    /// Exercise done beats a personal gain, which beats a milestone: the
    /// most specific news about what the lifter just did comes first. Nil
    /// for the last set of the workout, whose "every set done" status is
    /// the bigger moment.
    static func reward(
        entry: WorkoutExerciseEntry, gain: Gain?, before: Progress, after: Progress
    ) -> Reward? {
        guard after.remaining > 0 else { return nil }
        if entry.workingSetsDone { return .exerciseDone }
        if let gain, gain != .matched { return .gain(gain) }
        if let milestone = milestone(from: before.percent, to: after.percent) { return .milestone(milestone) }
        if let gain { return .gain(gain) }
        return .set(variant: after.done % 3)
    }
}
