import Foundation

/// Builds a one-day meal plan out of foods the user already eats — their
/// saved foods ("My Foods") and what they logged recently — scaled to hit
/// the calorie target within ±5% and the protein target or better.
///
/// Offline and deterministic: a greedy pick per slot, then coordinate
/// descent over every (food, portion) choice per slot until the day's
/// objective stops improving. Same inputs, same plan; "Regenerate"
/// passes the previous plan's foods as `avoiding` to get a different one.
enum MealPlanEngine {

    static let slots: [MealCategory] = [.breakfast, .lunch, .dinner, .snack]

    /// Share of the day's calories and protein each slot aims for before
    /// the day-level optimisation trades them off.
    static func share(of slot: MealCategory) -> Double {
        switch slot {
        case .breakfast: 0.25
        case .lunch:     0.35
        case .dinner:    0.30
        case .snack:     0.10
        }
    }

    /// Portion multipliers of a food's base serving — up to 3× so a
    /// 100 g library food can still make a full plate. The snack may
    /// also be dropped (0) when the three meals already land the day.
    static let portionSteps: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static let calorieTolerance = 0.05
    static let minimumFoods = 3
    static let historyWindowDays = 30

    // MARK: - Types

    /// One food the planner can pick, at its base serving.
    struct Food: Hashable, Identifiable, Sendable {
        /// `sourceID` when there is one, else the normalised name — the
        /// key that de-duplicates a food logged many times.
        let id: String
        let name: String
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        /// Slots the user has eaten it in. Empty = never logged, fits any.
        let slots: Set<MealCategory>
        let source: MealSource
        let sourceID: String?
        /// Ingredient snapshot at the base serving, scaled on log.
        let components: [MealFoodComponent]?
        /// "1 cup", "150 g" — what one base serving means.
        let servingLabel: String?

        func fits(_ slot: MealCategory) -> Bool { slots.isEmpty || slots.contains(slot) }
    }

    struct PlannedMeal: Hashable, Identifiable, Sendable {
        let slot: MealCategory
        let food: Food
        let portion: Double

        var id: MealCategory { slot }
        var calories: Int { Int((food.calories * portion).rounded()) }
        var proteinG: Int { Int((food.proteinG * portion).rounded()) }
        var carbsG: Int { Int((food.carbsG * portion).rounded()) }
        var fatG: Int { Int((food.fatG * portion).rounded()) }

        /// The diary entry one tap on this meal logs.
        func entry(at date: Date) -> MealEntry {
            MealEntry(
                date: date,
                category: slot,
                name: food.name,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                sourceID: food.sourceID,
                source: food.source,
                components: food.components?.map { component in
                    var scaled = component
                    scaled.grams = component.grams * portion
                    return scaled
                }
            )
        }
    }

    struct Plan: Hashable, Sendable {
        let meals: [PlannedMeal]
        let targetCalories: Int
        let targetProteinG: Int

        var calories: Int { meals.reduce(0) { $0 + $1.calories } }
        var proteinG: Int { meals.reduce(0) { $0 + $1.proteinG } }
        var carbsG: Int { meals.reduce(0) { $0 + $1.carbsG } }
        var fatG: Int { meals.reduce(0) { $0 + $1.fatG } }

        /// Signed fraction off the calorie target (+0.03 = 3% over).
        var calorieDeviation: Double {
            guard targetCalories > 0 else { return 0 }
            return Double(calories - targetCalories) / Double(targetCalories)
        }

        var isWithinCalorieTolerance: Bool { abs(calorieDeviation) <= MealPlanEngine.calorieTolerance }
        var meetsProtein: Bool { proteinG >= targetProteinG }
        var foodIDs: Set<String> { Set(meals.map(\.food.id)) }
    }

    enum Outcome: Hashable, Sendable {
        case plan(Plan)
        /// Fewer distinct foods than a plan needs; `found` is how many.
        case notEnoughFoods(found: Int)
    }

    // MARK: - Library

    /// Candidate foods: every saved custom food at its serving (or 100 g),
    /// plus each distinct meal logged in the last `historyWindowDays`,
    /// at the portion last logged. A custom food the user also logged
    /// keeps its library macros and learns the slots from the diary.
    static func foods(
        customFoods: [CustomFood],
        mealHistory: [MealEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [Food] {
        let cutoff = calendar.date(byAdding: .day, value: -historyWindowDays, to: now) ?? now
        let recent = mealHistory
            .filter { $0.date >= cutoff && $0.date <= now && $0.calories > 0 }
            .sorted { $0.date > $1.date }

        var slotsByKey: [String: Set<MealCategory>] = [:]
        for entry in recent {
            slotsByKey[key(for: entry), default: []].insert(entry.category)
        }

        var byID: [String: Food] = [:]
        for entry in recent where byID[key(for: entry)] == nil {
            let id = key(for: entry)
            byID[id] = Food(
                id: id,
                name: entry.name,
                calories: Double(entry.calories),
                proteinG: Double(entry.proteinG),
                carbsG: Double(entry.carbsG),
                fatG: Double(entry.fatG),
                slots: slotsByKey[id] ?? [],
                source: entry.source,
                sourceID: entry.sourceID,
                components: entry.components,
                servingLabel: nil
            )
        }
        for custom in customFoods {
            guard let food = libraryFood(from: custom, slots: slotsByKey[custom.foodID] ?? []) else { continue }
            byID[food.id] = food
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    private static func key(for entry: MealEntry) -> String {
        entry.sourceID ?? "name:" + entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func libraryFood(from custom: CustomFood, slots: Set<MealCategory>) -> Food? {
        let grams = custom.servingGrams.flatMap { $0 > 0 ? $0 : nil } ?? 100
        let scale = grams / 100
        let calories = custom.per100g.calories * scale
        guard calories.isFinite, calories > 0 else { return nil }
        let label = custom.servingLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Food(
            id: custom.foodID,
            name: custom.name,
            calories: calories,
            proteinG: custom.per100g.proteinG * scale,
            carbsG: custom.per100g.carbsG * scale,
            fatG: custom.per100g.fatG * scale,
            slots: slots,
            source: .custom,
            sourceID: custom.foodID,
            components: [MealFoodComponent(
                id: custom.foodID,
                name: custom.name,
                grams: grams,
                servingGrams: custom.servingGrams,
                servingLabel: custom.servingLabel,
                per100g: custom.per100g,
                sourceID: custom.foodID
            )],
            servingLabel: (label?.isEmpty ?? true) ? "\(Int(grams.rounded())) g" : label
        )
    }

    // MARK: - Planning

    static func generate(
        targets: NutritionTargets,
        foods: [Food],
        avoiding: Set<String> = []
    ) -> Outcome {
        guard foods.count >= minimumFoods else { return .notEnoughFoods(found: foods.count) }
        let foods = foods.sorted { $0.id < $1.id }
        let goal = Goal(targets: targets, avoiding: avoiding)
        var meals: [PlannedMeal] = []
        for slot in slots {
            if let pick = greedyPick(for: slot, foods: foods, taken: meals, goal: goal) {
                meals.append(pick)
            }
        }
        meals = optimise(meals, foods: foods, goal: goal, swappable: Set(slots), allowSkip: true)
        return .plan(Plan(meals: meals, targetCalories: targets.calories, targetProteinG: targets.proteinG))
    }

    /// Replaces the food in `slot` with the best *different* food, then
    /// re-tunes every portion around it so the day still lands.
    static func swapping(
        _ slot: MealCategory,
        in plan: Plan,
        foods: [Food],
        targets: NutritionTargets
    ) -> Plan {
        let foods = foods.sorted { $0.id < $1.id }
        let goal = Goal(targets: targets, avoiding: [])
        guard let index = plan.meals.firstIndex(where: { $0.slot == slot }) else { return plan }
        let current = plan.meals[index].food.id
        let alternatives = foods.filter { $0.id != current }
        var meals = plan.meals
        let others = meals.enumerated().filter { $0.offset != index }.map(\.element)
        guard let replacement = bestOption(for: slot, at: index, in: meals, foods: alternatives,
                                           taken: others, goal: goal, allowSkip: false) else { return plan }
        meals[index] = replacement
        // Portions only, and no dropping the snack: the user asked for a
        // different food in this slot, not a different day.
        meals = optimise(meals, foods: foods, goal: goal, swappable: [], allowSkip: false)
        return Plan(meals: meals, targetCalories: targets.calories, targetProteinG: targets.proteinG)
    }

    // MARK: - Internals

    private struct Goal {
        let calories: Double
        let proteinG: Double
        let avoiding: Set<String>

        init(targets: NutritionTargets, avoiding: Set<String>) {
            calories = Double(max(1, targets.calories))
            proteinG = Double(max(1, targets.proteinG))
            self.avoiding = avoiding
        }
    }

    private static func portions(for slot: MealCategory, allowSkip: Bool) -> [Double] {
        allowSkip && slot == .snack ? [0] + portionSteps : portionSteps
    }

    /// Foods allowed in `slot`: the ones eaten there before, or every food
    /// when none were, so a thin history never leaves a slot empty. Foods
    /// already in other slots are skipped unless nothing else is left.
    private static func eligible(_ foods: [Food], for slot: MealCategory, taken: [PlannedMeal]) -> [Food] {
        let used = Set(taken.filter { $0.portion > 0 }.map(\.food.id))
        let fresh = foods.filter { !used.contains($0.id) }
        let unused = fresh.isEmpty ? foods : fresh
        let fitting = unused.filter { $0.fits(slot) }
        return fitting.isEmpty ? unused : fitting
    }

    private static func greedyPick(
        for slot: MealCategory,
        foods: [Food],
        taken: [PlannedMeal],
        goal: Goal
    ) -> PlannedMeal? {
        let calorieBudget = goal.calories * share(of: slot)
        let proteinBudget = goal.proteinG * share(of: slot)
        var best: (meal: PlannedMeal, score: Double)?
        for food in eligible(foods, for: slot, taken: taken) {
            for portion in portionSteps {
                let meal = PlannedMeal(slot: slot, food: food, portion: portion)
                let calorieError = abs(Double(meal.calories) - calorieBudget) / calorieBudget
                let proteinShort = max(0, proteinBudget - Double(meal.proteinG)) / proteinBudget
                let score = calorieError + 1.5 * proteinShort + avoidPenalty(food, goal)
                if best == nil || score < (best?.score ?? .infinity) - 1e-9 {
                    best = (meal, score)
                }
            }
        }
        return best?.meal
    }

    private static func optimise(
        _ start: [PlannedMeal],
        foods: [Food],
        goal: Goal,
        swappable: Set<MealCategory>,
        allowSkip: Bool
    ) -> [PlannedMeal] {
        var meals = start
        var current = objective(meals, goal: goal)
        for _ in 0..<12 {
            var improved = false
            for index in meals.indices {
                let slot = meals[index].slot
                let others = meals.enumerated().filter { $0.offset != index }.map(\.element)
                let pool = swappable.contains(slot) ? foods : [meals[index].food]
                guard let candidate = bestOption(for: slot, at: index, in: meals, foods: pool,
                                                 taken: others, goal: goal, allowSkip: allowSkip) else { continue }
                var trial = meals
                trial[index] = candidate
                let score = objective(trial, goal: goal)
                if score < current - 1e-9 {
                    meals = trial
                    current = score
                    improved = true
                }
            }
            if !improved { break }
        }
        return meals.filter { $0.portion > 0 }
    }

    /// The (food, portion) for `slot` that minimises the whole day's
    /// objective with every other slot held fixed.
    private static func bestOption(
        for slot: MealCategory,
        at index: Int,
        in meals: [PlannedMeal],
        foods: [Food],
        taken: [PlannedMeal],
        goal: Goal,
        allowSkip: Bool
    ) -> PlannedMeal? {
        var best: (meal: PlannedMeal, score: Double)?
        var trial = meals
        for food in eligible(foods, for: slot, taken: taken) {
            for portion in portions(for: slot, allowSkip: allowSkip) {
                let meal = PlannedMeal(slot: slot, food: food, portion: portion)
                trial[index] = meal
                let score = objective(trial, goal: goal)
                if best == nil || score < (best?.score ?? .infinity) - 1e-9 {
                    best = (meal, score)
                }
            }
        }
        return best?.meal
    }

    /// Lower is better. Calorie error outside the ±5% band and any
    /// protein shortfall dominate; inside the band, slot balance and
    /// portions near one serving break ties toward a sensible-looking day.
    private static func objective(_ meals: [PlannedMeal], goal: Goal) -> Double {
        let live = meals.filter { $0.portion > 0 }
        let calories = Double(live.reduce(0) { $0 + $1.calories })
        let protein = Double(live.reduce(0) { $0 + $1.proteinG })

        let calorieError = abs(calories - goal.calories) / goal.calories
        let outsideBand = max(0, calorieError - calorieTolerance)
        let proteinShort = max(0, goal.proteinG - protein) / goal.proteinG

        let balance = meals.reduce(0.0) { total, meal in
            let mealCalories = meal.portion > 0 ? Double(meal.calories) : 0
            return total + abs(mealCalories - goal.calories * share(of: meal.slot)) / goal.calories
        }
        let portionDrift = live.reduce(0.0) { $0 + abs($1.portion - 1) }
        let avoided = live.reduce(0.0) { $0 + avoidPenalty($1.food, goal) }

        return calorieError + 10 * outsideBand + 5 * proteinShort
            + 0.1 * balance + 0.005 * portionDrift + avoided
    }

    /// Cost of reusing a food "Regenerate" asked to move away from: big
    /// enough to pick a fresh food when one fits the day, small enough to
    /// keep a repeat over missing the targets.
    private static let variationPenalty = 0.1

    private static func avoidPenalty(_ food: Food, _ goal: Goal) -> Double {
        goal.avoiding.contains(food.id) ? variationPenalty : 0
    }
}
