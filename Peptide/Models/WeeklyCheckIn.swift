import Foundation

/// The rule-based weekly check-in: the last seven days against the seven
/// before them. Built by `WeeklyCheckInEngine` from data already on the
/// profile, Health and the workout log; never persisted. Each section is
/// nil when there is nothing to say about it, so the card shows only what
/// the user actually logged.
struct WeeklyCheckIn: Equatable, Sendable {
    let weight: Weight?
    let nutrition: Nutrition?
    let training: Training?
    let sleep: Sleep?
    let suggestion: Suggestion

    struct Weight: Equatable, Sendable {
        /// Average of this week's weigh-ins, or the latest reading when
        /// this week has none.
        let currentKg: Double
        /// This week's average minus last week's. Nil until both weeks
        /// have at least one weigh-in.
        let changeKgPerWeek: Double?
        let weighInsThisWeek: Int
        /// Exponentially smoothed trend at each weigh-in of the two weeks,
        /// oldest first, for the sparkline.
        let trend: [Point]
    }

    struct Point: Equatable, Sendable {
        let date: Date
        let kg: Double
    }

    struct Nutrition: Equatable, Sendable {
        let loggedDays: Int
        let averageKcal: Int
        let previousAverageKcal: Int?
        let targetKcal: Int?
        /// Share of logged days within ±10% of the calorie target.
        let kcalAdherence: Double?
        let averageProteinG: Int
        let targetProteinG: Int?
        /// Share of logged days reaching at least 90% of the protein
        /// target. Going over is never a miss.
        let proteinAdherence: Double?
    }

    struct Training: Equatable, Sendable {
        /// Distinct days with a workout.
        let days: Int
        let previousDays: Int
        let goal: Int?
        let goalSource: GoalSource?

        enum GoalSource: Equatable, Sendable {
            /// The days per week the user set in training preferences.
            case planned
            /// The average of the three weeks before this one.
            case usual
        }
    }

    struct Sleep: Equatable, Sendable {
        let averageHours: Double
        let previousAverageHours: Double?
    }

    /// One thing to change next week, most important first.
    enum Suggestion: Equatable, Sendable {
        case hitCalorieTarget
        case weightStalledEatLess(kcal: Int)
        case weightStalledEatMore(kcal: Int)
        case losingFast(kcal: Int)
        case gainingFast(kcal: Int)
        case prioritizeProtein
        case planWorkouts(goal: Int)
        case prioritizeSleep
        case weighInMore
        case keepGoing
    }
}
