import XCTest
@testable import Peptide

final class WeeklyPrepEngineTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-10-28 is a Wednesday in ISO week 44.
    private func date(day: Int = 28, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func ingredient(_ key: String, grams: Double = 100) -> LibraryRecipe.Ingredient {
        LibraryRecipe.Ingredient(name: key.capitalized, nameSV: "\(key) sv", grams: grams, pantryKey: key)
    }

    private func recipe(
        _ id: String,
        ingredients: [LibraryRecipe.Ingredient],
        protein: Double = 40,
        category: MealCategory = .lunch,
        mealPrep: Bool = true,
        minutes: Int = 30,
        servings: Int = 4,
        fridgeDays: Int? = 4,
        steps: [String] = ["Chop.", "Fry.", "Divide into boxes."]
    ) -> LibraryRecipe {
        LibraryRecipe(
            id: id,
            name: id.capitalized,
            nameSV: "\(id) sv",
            category: category,
            mealPrep: mealPrep,
            minutes: minutes,
            servings: servings,
            fridgeDays: fridgeDays,
            tags: ["meal-prep"],
            ingredients: ingredients,
            steps: steps,
            stepsSV: steps,
            calories: 500,
            proteinG: protein,
            carbsG: 50,
            fatG: 10,
            fiberG: 6,
            micros: LibraryRecipe.Micros(sodiumMg: 0, potassiumMg: 0, ironMg: 0, calciumMg: 0, vitaminDUg: 0, vitaminB12Ug: 0),
            image: "recipe-\(id)"
        )
    }

    private func context(now: Date? = nil, pantry: Set<String> = []) -> RecipeLibraryEngine.Context {
        RecipeLibraryEngine.Context(now: now ?? date(), calendar: calendar, pantry: pantry)
    }

    private func byID(_ recipes: [LibraryRecipe]) -> [String: LibraryRecipe] {
        Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    }

    // MARK: - Weeks

    func test_weekStart_midweek_isMondayMidnight() {
        let start = WeeklyPrepEngine.weekStart(for: date(), calendar: calendar)
        XCTAssertEqual(start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        XCTAssertEqual(WeeklyPrepEngine.weekNumber(for: date(), calendar: calendar), 44)
    }

    func test_weekStart_sunday_staysInSameISOWeek() {
        let sunday = date(day: 1, month: 11, hour: 20)
        XCTAssertEqual(
            WeeklyPrepEngine.weekStart(for: sunday, calendar: calendar),
            WeeklyPrepEngine.weekStart(for: date(), calendar: calendar)
        )
    }

    func test_plan_newWeek_startsEmptyAndLastWeekFeedsVariety() {
        let lastWeek = PrepWeek(
            weekStart: WeeklyPrepEngine.weekStart(for: date(), calendar: calendar),
            dishes: [PrepDish(recipeID: "a", servings: 4)],
            bought: ["rice"]
        )
        let nextMonday = date(day: 2, month: 11, hour: 8)

        let plan = WeeklyPrepEngine.plan(for: nextMonday, in: [lastWeek], calendar: calendar)

        XCTAssertTrue(plan.dishes.isEmpty)
        XCTAssertTrue(plan.bought.isEmpty)
        XCTAssertEqual(plan.weekStart, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        XCTAssertEqual(WeeklyPrepEngine.recentRecipeIDs(in: [lastWeek], before: nextMonday, calendar: calendar), ["a"])
    }

    func test_recentRecipeIDs_threeWeeksAgo_isForgotten() {
        let old = PrepWeek(
            weekStart: WeeklyPrepEngine.weekStart(for: date(day: 7), calendar: calendar),
            dishes: [PrepDish(recipeID: "old", servings: 4)]
        )
        XCTAssertTrue(WeeklyPrepEngine.recentRecipeIDs(in: [old], before: date(), calendar: calendar).isEmpty)
    }

    // MARK: - Suggestion

    func test_suggestWeek_picksTwoDistinctMealPrepDishesWithDifferentProteins() {
        let recipes = [
            recipe("chicken-a", ingredients: [ingredient("chicken breast"), ingredient("rice")], protein: 50),
            recipe("chicken-b", ingredients: [ingredient("chicken thigh"), ingredient("rice")], protein: 48),
            recipe("salmon", ingredients: [ingredient("salmon"), ingredient("potato")], protein: 35),
            recipe("oats", ingredients: [ingredient("oat")], protein: 60, category: .breakfast),
            recipe("not-prep", ingredients: [ingredient("beef")], protein: 70, mealPrep: false),
        ]

        let ranked = WeeklyPrepEngine.ranked(recipes, context: context(), recentRecipeIDs: [])
        let week = WeeklyPrepEngine.suggestWeek(from: ranked)

        XCTAssertEqual(week.map(\.recipeID), ["chicken-a", "salmon"])
        XCTAssertEqual(week.map(\.servings), [4, 4])
    }

    func test_suggestWeek_recentDish_isRankedBelowFreshOne() {
        let recipes = [
            recipe("chicken", ingredients: [ingredient("chicken breast")], protein: 50),
            recipe("beef", ingredients: [ingredient("minced beef")], protein: 45),
            recipe("lentils", ingredients: [ingredient("lentil")], protein: 30),
        ]

        let ranked = WeeklyPrepEngine.ranked(recipes, context: context(), recentRecipeIDs: ["chicken"])
        let week = WeeklyPrepEngine.suggestWeek(from: ranked)

        XCTAssertEqual(week.map(\.recipeID), ["beef", "lentils"])
    }

    func test_suggestWeek_onlyOneProtein_stillFillsTheWeek() {
        let recipes = [
            recipe("chicken-a", ingredients: [ingredient("chicken breast")]),
            recipe("chicken-b", ingredients: [ingredient("chicken thigh")]),
        ]
        let week = WeeklyPrepEngine.suggestWeek(from: recipes)
        XCTAssertEqual(week.count, 2)
    }

    func test_suggestWeek_bundledLibrary_givesTwoMealPrepBoxes() {
        let library = RecipeLibraryEngine.bundled
        guard !library.isEmpty else { return }
        let week = WeeklyPrepEngine.suggestWeek(
            from: WeeklyPrepEngine.ranked(library, context: context(), recentRecipeIDs: [])
        )
        let recipes = byID(library)
        let picked = week.compactMap { recipes[$0.recipeID] }
        XCTAssertEqual(picked.count, 2)
        XCTAssertTrue(picked.allSatisfy(\.mealPrep))
        XCTAssertNotEqual(WeeklyPrepEngine.mainProtein(of: picked[0]), WeeklyPrepEngine.mainProtein(of: picked[1]))
    }

    // MARK: - Shopping list

    func test_shoppingList_sharedIngredient_mergesAndScalesByServings() {
        let first = recipe("a", ingredients: [ingredient("chicken breast", grams: 150), ingredient("brown rice", grams: 70)])
        let second = recipe("b", ingredients: [ingredient("salmon", grams: 120), ingredient("brown rice", grams: 60)])
        let dishes = [PrepDish(recipeID: "a", servings: 4), PrepDish(recipeID: "b", servings: 2)]

        let list = WeeklyPrepEngine.shoppingList(for: dishes, recipes: byID([first, second]), pantry: [])

        XCTAssertEqual(list.map(\.pantryKey), ["chicken breast", "brown rice", "salmon"])
        XCTAssertEqual(list.first { $0.pantryKey == "brown rice" }?.grams, 70 * 4 + 60 * 2)
        XCTAssertEqual(list.first { $0.pantryKey == "chicken breast" }?.grams, 600)
    }

    func test_shoppingList_pantryItem_isMarkedAtHomeAndSortedLast() {
        let dish = recipe("a", ingredients: [ingredient("rapeseed oil"), ingredient("brown rice")])
        let list = WeeklyPrepEngine.shoppingList(
            for: [PrepDish(recipeID: "a", servings: 4)],
            recipes: byID([dish]),
            pantry: ["rapeseed oil"]
        )

        XCTAssertEqual(list.first { $0.pantryKey == "rapeseed oil" }?.isAtHome, true)
        XCTAssertEqual(list.first { $0.pantryKey == "brown rice" }?.isAtHome, false)
        let pantryShelf = WeeklyPrepEngine.grouped(list).first { $0.section == .pantry }
        XCTAssertEqual(pantryShelf?.items.map(\.pantryKey), ["brown rice", "rapeseed oil"])
    }

    func test_grouped_sections_followStoreOrder() {
        let dish = recipe("a", ingredients: [
            ingredient("soy sauce"), ingredient("yogurt"), ingredient("salmon"), ingredient("broccoli"), ingredient("green pea"),
        ])
        let list = WeeklyPrepEngine.shoppingList(for: [PrepDish(recipeID: "a", servings: 4)], recipes: byID([dish]), pantry: [])

        XCTAssertEqual(WeeklyPrepEngine.grouped(list).map(\.section), [.produce, .meatAndFish, .dairy, .frozen, .pantry])
    }

    // MARK: - Prep day

    func test_prepTasks_slowStepsFirstThenCookingThenPacking() {
        let stew = recipe("stew", ingredients: [ingredient("beef")], minutes: 90, steps: [
            "Brown the beef.", "Simmer for an hour.", "Divide into boxes.",
        ])
        let bowl = recipe("bowl", ingredients: [ingredient("chicken breast")], minutes: 30, steps: [
            "Cook the rice.", "Fry the chicken.", "Pack.",
        ])
        let dishes = [PrepDish(recipeID: "bowl", servings: 4), PrepDish(recipeID: "stew", servings: 5)]

        let tasks = WeeklyPrepEngine.prepTasks(for: dishes, recipes: byID([stew, bowl]))

        XCTAssertEqual(tasks.map(\.id), [
            "bowl#step0",
            "stew#step0", "stew#step1", "bowl#step1",
            "stew#step2", "stew#portion", "bowl#step2", "bowl#portion", "cool",
        ])
        XCTAssertEqual(tasks.first { $0.id == "stew#portion" }?.kind, .portion(boxes: 5))
        XCTAssertEqual(tasks.first?.phase, .start)
        XCTAssertEqual(tasks.last?.kind, .cool)
    }

    // MARK: - Boxes

    func test_eatBy_fridgeBox_isCookedDayPlusFridgeDays() {
        let batch = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(day: 1, month: 11, hour: 15), frozenAt: nil, count: 4)
        let eatBy = WeeklyPrepEngine.eatBy(batch, fridgeDays: 4, calendar: calendar)

        XCTAssertEqual(eatBy, calendar.date(from: DateComponents(year: 2026, month: 11, day: 5)))
        XCTAssertEqual(WeeklyPrepEngine.freshness(eatBy: eatBy, now: date(day: 2, month: 11), calendar: calendar), .fresh)
        XCTAssertEqual(WeeklyPrepEngine.freshness(eatBy: eatBy, now: date(day: 4, month: 11), calendar: calendar), .soon)
        XCTAssertEqual(WeeklyPrepEngine.freshness(eatBy: eatBy, now: date(day: 5, month: 11, hour: 22), calendar: calendar), .soon)
        XCTAssertEqual(WeeklyPrepEngine.freshness(eatBy: eatBy, now: date(day: 6, month: 11), calendar: calendar), .expired)
    }

    func test_eatBy_frozenBox_keepsThreeMonths() {
        let batch = PrepBoxBatch(
            id: UUID(), recipeID: "a", cookedAt: date(day: 1, month: 11), frozenAt: date(day: 2, month: 11), count: 1
        )
        let eatBy = WeeklyPrepEngine.eatBy(batch, fridgeDays: 4, calendar: calendar)

        XCTAssertEqual(eatBy, calendar.date(from: DateComponents(year: 2027, month: 2, day: 2)))
        XCTAssertEqual(WeeklyPrepEngine.freshness(eatBy: eatBy, now: date(day: 20, month: 12), calendar: calendar), .fresh)
    }

    func test_boxes_afterPrep_makeOneBatchPerDishWithItsServings() {
        let batches = WeeklyPrepEngine.boxes(
            for: [PrepDish(recipeID: "a", servings: 4), PrepDish(recipeID: "b", servings: 5)],
            cookedAt: date()
        )
        XCTAssertEqual(batches.map(\.count), [4, 5])
        XCTAssertTrue(batches.allSatisfy { !$0.isFrozen })
    }

    func test_removingOne_decrementsAndDropsEmptyBatch() {
        let batch = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(), frozenAt: nil, count: 2)

        let once = WeeklyPrepEngine.removingOne(from: [batch], id: batch.id)
        XCTAssertEqual(once.first?.count, 1)

        let twice = WeeklyPrepEngine.removingOne(from: once, id: batch.id)
        XCTAssertTrue(twice.isEmpty)
    }

    func test_freezingOne_movesABoxAndJoinsFrozenBatch() {
        let fridge = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(), frozenAt: nil, count: 4)

        let once = WeeklyPrepEngine.freezingOne(from: [fridge], id: fridge.id, at: date(day: 29))
        let twice = WeeklyPrepEngine.freezingOne(from: once, id: fridge.id, at: date(day: 30))

        XCTAssertEqual(twice.first { !$0.isFrozen }?.count, 2)
        XCTAssertEqual(twice.filter(\.isFrozen).count, 1)
        XCTAssertEqual(twice.first(where: \.isFrozen)?.count, 2)
        XCTAssertEqual(twice.first(where: \.isFrozen)?.frozenAt, date(day: 29))
    }

    func test_pruned_longExpiredBatch_isDropped() {
        let dish = recipe("a", ingredients: [ingredient("rice")], fridgeDays: 3)
        let stale = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(day: 1), frozenAt: nil, count: 2)
        let recent = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(day: 25), frozenAt: nil, count: 2)

        let kept = WeeklyPrepEngine.pruned([stale, recent], recipes: byID([dish]), now: date(), calendar: calendar)

        XCTAssertEqual(kept.map(\.id), [recent.id])
    }

    func test_nextReminder_isEveningBeforeSoonestFridgeEatBy() {
        let dish = recipe("a", ingredients: [ingredient("rice")], fridgeDays: 3)
        let fridge = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(day: 1, month: 11), frozenAt: nil, count: 2)
        let frozen = PrepBoxBatch(id: UUID(), recipeID: "a", cookedAt: date(), frozenAt: date(), count: 1)

        let reminder = WeeklyPrepEngine.nextReminder(
            for: [frozen, fridge], recipes: byID([dish]), now: date(day: 1, month: 11, hour: 18), calendar: calendar
        )

        XCTAssertEqual(reminder?.fireDate, date(day: 3, month: 11, hour: 18))
        XCTAssertEqual(reminder?.recipeIDs, ["a"])
    }
}
