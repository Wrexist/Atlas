import Foundation

/// The things that make a day "logged" — the three main meals, the
/// day's training (or rest), the step goal, water, and the morning
/// weigh-in — reduced to one value Today's checklist renders. Pure so the
/// done-rules live in one tested place.
enum TodayChecklistEngine {
    enum Item: String, CaseIterable, Identifiable, Sendable {
        case meals, training, steps, water, weight
        var id: String { rawValue }
    }

    /// The meals the checklist counts. Snacks are a bonus, not a gap.
    static let mainMeals: [MealCategory] = [.breakfast, .lunch, .dinner]

    /// Daily water goal in fluid ounces — the same target the Meals tab's
    /// water ring fills toward.
    static let waterTargetOz = 100

    struct State: Equatable, Sendable {
        var loggedMeals: Set<MealCategory>
        var trainedToday: Bool
        var isTrainingDay: Bool
        var waterFluidOunces: Double
        var weightTodayKg: Double?
        /// The meal whose time-of-day window `now` falls in; `.snack`
        /// outside all three.
        var currentMeal: MealCategory
        /// The day's steps from Health; nil when Health has no step
        /// data, which drops the steps row instead of leaving it
        /// unreachable.
        var steps: Double? = nil
        var stepGoal: Int = StepGoalEngine.defaultGoal

        /// The rows this day has, in display order.
        var items: [Item] {
            Item.allCases.filter { $0 != .steps || steps != nil }
        }

        /// The first unlogged main meal from the current window on. Nil
        /// once every remaining window has passed, so a skipped
        /// breakfast isn't pitched as "next" in the evening.
        var nextMeal: MealCategory? {
            let mains = TodayChecklistEngine.mainMeals
            guard let current = mains.firstIndex(of: currentMeal) else { return nil }
            return mains[current...].first { !loggedMeals.contains($0) }
        }

        var loggedMainMealCount: Int {
            TodayChecklistEngine.mainMeals.filter(loggedMeals.contains).count
        }

        var waterProgress: Double {
            min(1, waterFluidOunces / Double(TodayChecklistEngine.waterTargetOz))
        }

        var stepProgress: Double {
            StepGoalEngine.progress(steps: steps ?? 0, goal: stepGoal)
        }

        func isDone(_ item: Item) -> Bool {
            switch item {
            case .meals:    loggedMainMealCount == TodayChecklistEngine.mainMeals.count
            // A rest day is a planned outcome, so it counts as done.
            case .training: trainedToday || !isTrainingDay
            case .steps:    steps.map { StepGoalEngine.isMet(steps: $0, goal: stepGoal) } ?? false
            case .water:    waterProgress >= 1
            case .weight:   weightTodayKg != nil
            }
        }

        var completedCount: Int {
            items.filter(isDone).count
        }
    }

    static func state(
        profile: UserProfile,
        consumption: DailyConsumption,
        trainedToday: Bool,
        steps: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> State {
        let preferredDays = profile.trainingPreferences?.preferredDays ?? []
        let weekday = calendar.component(.weekday, from: now)
        return State(
            loggedMeals: Set(profile.mealHistory
                .filter { calendar.isDate($0.date, inSameDayAs: now) }
                .map(\.category)),
            trainedToday: trainedToday,
            isTrainingDay: preferredDays.isEmpty || preferredDays.contains { $0.calendarWeekdayValue == weekday },
            waterFluidOunces: consumption.waterFluidOunces,
            weightTodayKg: profile.weightHistory
                .filter { calendar.isDate($0.date, inSameDayAs: now) }
                .max { $0.date < $1.date }?
                .kg,
            currentMeal: MealCategory.auto(for: now, calendar: calendar),
            steps: steps,
            stepGoal: (profile.trainingPreferences ?? TrainingPreferences()).stepGoal
        )
    }

    /// One tap on the water row: a 250 mL glass in metric, 8 oz in
    /// imperial — the smallest quick-add chip on the Meals tab.
    static func glassFluidOunces(for unit: MeasurementUnit) -> Double {
        unit == .metric ? 250 / 29.5735 : 8
    }
}
