import Foundation

/// The four things that make a day "logged" — the three main meals, the
/// day's training (or rest), water, and the morning weigh-in — reduced to
/// one value Today's checklist renders. Pure so the done-rules live in one
/// tested place.
enum TodayChecklistEngine {
    enum Item: String, CaseIterable, Identifiable, Sendable {
        case meals, training, water, weight
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

        /// The first main meal not yet logged, in day order.
        var nextMeal: MealCategory? {
            TodayChecklistEngine.mainMeals.first { !loggedMeals.contains($0) }
        }

        var loggedMainMealCount: Int {
            TodayChecklistEngine.mainMeals.filter(loggedMeals.contains).count
        }

        var waterProgress: Double {
            min(1, waterFluidOunces / Double(TodayChecklistEngine.waterTargetOz))
        }

        func isDone(_ item: Item) -> Bool {
            switch item {
            case .meals:    nextMeal == nil
            // A rest day is a planned outcome, so it counts as done.
            case .training: trainedToday || !isTrainingDay
            case .water:    waterProgress >= 1
            case .weight:   weightTodayKg != nil
            }
        }

        var completedCount: Int {
            Item.allCases.filter(isDone).count
        }
    }

    static func state(
        profile: UserProfile,
        consumption: DailyConsumption,
        trainedToday: Bool,
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
                .kg
        )
    }

    /// One tap on the water row: a 250 mL glass in metric, 8 oz in
    /// imperial — the smallest quick-add chip on the Meals tab.
    static func glassFluidOunces(for unit: MeasurementUnit) -> Double {
        unit == .metric ? 250 / 29.5735 : 8
    }
}
