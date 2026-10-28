import Foundation

extension DataStore {
    /// The weekly check-in from the store's own history. Sleep comes from
    /// Health, so the caller fetches it and passes it in.
    func weeklyCheckIn(sleepHours: [(date: Date, value: Double)], now: Date = Date()) -> WeeklyCheckIn? {
        WeeklyCheckInEngine.build(
            weights: dedupedWeightHistory,
            consumption: Array(profile.dailyConsumption.values),
            targets: profile.nutritionTargets,
            goalRaw: profile.primaryGoal,
            // Four weeks: the usual-week baseline averages the three
            // before this one.
            workoutDates: recentWorkoutDates(days: 28),
            plannedWorkoutsPerWeek: profile.trainingPreferences?.daysPerWeek,
            sleepHours: sleepHours,
            now: now,
            calendar: .current
        )
    }
}
