import Foundation

/// The daily step goal and the day's progress toward it. Pure so the
/// clamping, progress and "which count belongs to this day" rules live
/// in one tested place; Today's checklist row, the Steps card and the
/// Profile stepper all read through here.
enum StepGoalEngine {
    static let defaultGoal = 8_000
    /// What the Profile stepper offers. Below 1 000 the goal is met by
    /// walking around the house; above 50 000 it's a typo.
    static let goalRange = 1_000...50_000
    static let goalIncrement = 500
    /// How often Today re-reads its step count while it stays on screen.
    static let liveRefreshSeconds = 300

    /// The goal Today counts toward: the saved one, kept inside
    /// `goalRange`, or the default when none was ever saved.
    static func goal(stored: Int?) -> Int {
        clamped(stored ?? defaultGoal)
    }

    static func clamped(_ goal: Int) -> Int {
        min(max(goal, goalRange.lowerBound), goalRange.upperBound)
    }

    /// Fraction of `goal` walked, 0…1.
    static func progress(steps: Double, goal: Int) -> Double {
        guard goal > 0, steps > 0 else { return 0 }
        return min(1, steps / Double(goal))
    }

    static func isMet(steps: Double, goal: Int) -> Bool {
        goal > 0 && steps >= Double(goal)
    }

    /// Days of Health step history Today fetches: every day its day
    /// switcher reaches, today included. A window sized to the shown day
    /// left the next day back outside it, so paging back dropped the
    /// steps row until a refetch put it back. A window longer than a day
    /// also tells "Health has no step data at all" apart from "no steps
    /// yet today".
    static let fetchDays = LifestyleDataLogic.maxMealDayLookback + 1
    /// Days the live tick re-reads while Today stays open: today, plus
    /// yesterday for a late Watch sync. Older days are final, so the
    /// tick doesn't re-run the year-long query.
    static let recentFetchDays = 2

    /// `full` with its last `recentFetchDays` days replaced by `recent`,
    /// a fresh read of just those days. A day `recent` has no bucket for
    /// walked 0, so it drops out rather than keeping a stale count.
    static func merging(
        recent: [(date: Date, value: Double)],
        into full: [(date: Date, value: Double)],
        now: Date,
        calendar: Calendar = .current
    ) -> [(date: Date, value: Double)] {
        guard let cutoff = calendar.date(
            byAdding: .day,
            value: -(recentFetchDays - 1),
            to: calendar.startOfDay(for: now)
        ) else { return full }
        return full.filter { $0.date < cutoff } + recent
    }

    /// Steps on `day` from Health's daily buckets, which only hold days
    /// that have samples. Nil when the window has no step data at all
    /// (Health not sharing steps) or `day` precedes it, so a reader that
    /// never sees steps isn't shown a goal it can't reach; a day inside
    /// the window without a bucket walked 0.
    static func steps(
        on day: Date,
        from buckets: [(date: Date, value: Double)],
        calendar: Calendar = .current
    ) -> Double? {
        guard let earliest = buckets.map(\.date).min(),
              calendar.startOfDay(for: day) >= calendar.startOfDay(for: earliest) else { return nil }
        return buckets.first { calendar.isDate($0.date, inSameDayAs: day) }?.value ?? 0
    }
}
