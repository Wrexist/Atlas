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
    /// Days of Health step history fetched for today, so "Health has no
    /// step data at all" can be told apart from "no steps yet today".
    static let lookbackDays = 7

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

    /// How many days back to fetch so the window covers the day
    /// `dayOffset` days from today (0 = today, -1 = yesterday).
    static func fetchDays(forDayOffset dayOffset: Int) -> Int {
        max(lookbackDays, 1 - min(dayOffset, 0))
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
