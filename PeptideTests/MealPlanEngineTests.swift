import XCTest
@testable import Peptide

final class MealPlanEngineTests: XCTestCase {

    private func food(
        _ id: String,
        kcal: Double,
        protein: Double,
        slots: Set<MealCategory> = []
    ) -> MealPlanEngine.Food {
        MealPlanEngine.Food(
            id: "custom:\(id)",
            name: id.capitalized,
            calories: kcal,
            proteinG: protein,
            carbsG: 0,
            fatG: 0,
            slots: slots,
            source: .custom,
            sourceID: "custom:\(id)",
            components: nil,
            servingLabel: nil
        )
    }

    private var library: [MealPlanEngine.Food] {
        [
            food("oats", kcal: 300, protein: 10, slots: [.breakfast]),
            food("yogurt", kcal: 190, protein: 20, slots: [.breakfast, .snack]),
            food("eggs", kcal: 140, protein: 12, slots: [.breakfast]),
            food("chicken", kcal: 330, protein: 62, slots: [.lunch, .dinner]),
            food("rice", kcal: 195, protein: 4, slots: [.lunch, .dinner]),
            food("salmon", kcal: 310, protein: 30, slots: [.dinner]),
            food("whey", kcal: 120, protein: 24, slots: [.snack]),
            food("banana", kcal: 105, protein: 1, slots: [.snack]),
        ]
    }

    private func targets(_ calories: Int, _ protein: Int) -> NutritionTargets {
        NutritionTargets(calories: calories, proteinG: protein, carbsG: 0, fatG: 0, fiberG: 30)
    }

    private func plan(_ outcome: MealPlanEngine.Outcome, file: StaticString = #filePath, line: UInt = #line) -> MealPlanEngine.Plan? {
        guard case .plan(let plan) = outcome else {
            XCTFail("Expected a plan, got \(outcome)", file: file, line: line)
            return nil
        }
        return plan
    }

    // MARK: - Hitting targets

    func test_generate_feasibleTargets_landWithinFivePercentAndMeetProtein() {
        for (calories, protein) in [(2000, 150), (1650, 150), (2575, 175), (2400, 120), (1800, 130)] {
            guard let result = plan(MealPlanEngine.generate(targets: targets(calories, protein), foods: library)) else { continue }
            XCTAssertTrue(result.isWithinCalorieTolerance,
                          "\(calories) kcal target planned at \(result.calories)")
            XCTAssertTrue(result.meetsProtein,
                          "\(protein) g protein target planned at \(result.proteinG)")
        }
    }

    func test_generate_placesFoodsInSlotsTheyWereEatenIn() {
        guard let result = plan(MealPlanEngine.generate(targets: targets(2000, 150), foods: library)) else { return }
        XCTAssertFalse(result.meals.isEmpty)
        for meal in result.meals {
            XCTAssertTrue(meal.food.fits(meal.slot), "\(meal.food.name) planned for \(meal.slot)")
        }
        XCTAssertEqual(result.foodIDs.count, result.meals.count, "Each meal should be a different food")
    }

    func test_generate_isDeterministicRegardlessOfInputOrder() {
        let first = MealPlanEngine.generate(targets: targets(2000, 150), foods: library)
        let second = MealPlanEngine.generate(targets: targets(2000, 150), foods: Array(library.reversed()))
        XCTAssertEqual(first, second)
    }

    func test_generate_avoidingPreviousPlan_picksDifferentFoods() {
        guard let original = plan(MealPlanEngine.generate(targets: targets(2000, 150), foods: library)),
              let regenerated = plan(MealPlanEngine.generate(
                  targets: targets(2000, 150), foods: library, avoiding: original.foodIDs
              ))
        else { return }
        XCTAssertNotEqual(original.foodIDs, regenerated.foodIDs)
        XCTAssertTrue(regenerated.isWithinCalorieTolerance)
        XCTAssertTrue(regenerated.meetsProtein)
    }

    func test_swapping_replacesOnlyThatSlotsFood() {
        guard let original = plan(MealPlanEngine.generate(targets: targets(2000, 150), foods: library)),
              let lunch = original.meals.first(where: { $0.slot == .lunch })
        else { return XCTFail("Expected a lunch") }
        let swapped = MealPlanEngine.swapping(.lunch, in: original, foods: library, targets: targets(2000, 150))
        let newLunch = swapped.meals.first { $0.slot == .lunch }
        XCTAssertNotNil(newLunch)
        XCTAssertNotEqual(newLunch?.food.id, lunch.food.id)
        XCTAssertEqual(swapped.meals.map(\.slot), original.meals.map(\.slot))
        let unchanged = original.meals.filter { $0.slot != .lunch }.map(\.food.id)
        XCTAssertEqual(swapped.meals.filter { $0.slot != .lunch }.map(\.food.id), unchanged)
    }

    // MARK: - Small or unsuitable libraries

    func test_generate_tooFewFoods_reportsHowManyWereFound() {
        XCTAssertEqual(MealPlanEngine.generate(targets: targets(2000, 150), foods: []), .notEnoughFoods(found: 0))
        XCTAssertEqual(
            MealPlanEngine.generate(targets: targets(2000, 150), foods: Array(library.prefix(2))),
            .notEnoughFoods(found: 2)
        )
    }

    func test_generate_threeFoods_stillFillsTheDay() {
        let small = [food("a", kcal: 400, protein: 30), food("b", kcal: 250, protein: 25), food("c", kcal: 150, protein: 5)]
        guard let result = plan(MealPlanEngine.generate(targets: targets(2000, 150), foods: small)) else { return }
        XCTAssertTrue(result.isWithinCalorieTolerance)
        XCTAssertTrue(result.meetsProtein)
    }

    func test_generate_lowProteinLibrary_returnsHonestShortfall() {
        let low = [food("bread", kcal: 250, protein: 8), food("jam", kcal: 100, protein: 0), food("juice", kcal: 120, protein: 1)]
        guard let result = plan(MealPlanEngine.generate(targets: targets(2000, 150), foods: low)) else { return }
        XCTAssertTrue(result.isWithinCalorieTolerance)
        XCTAssertFalse(result.meetsProtein)
    }

    // MARK: - Library building

    func test_foods_dedupesDiaryAndLearnsSlots() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let history = [
            MealEntry(date: now.addingTimeInterval(-86_400), category: .breakfast, name: "Porridge",
                      calories: 350, proteinG: 12, carbsG: 55, fatG: 8, source: .manual),
            MealEntry(date: now.addingTimeInterval(-3_600), category: .snack, name: "porridge ",
                      calories: 300, proteinG: 10, carbsG: 50, fatG: 7, source: .manual),
            MealEntry(date: now.addingTimeInterval(-3_600), category: .lunch, name: "Water",
                      calories: 0, proteinG: 0, carbsG: 0, fatG: 0, source: .manual),
            MealEntry(date: now.addingTimeInterval(-40 * 86_400), category: .dinner, name: "Old stew",
                      calories: 600, proteinG: 30, carbsG: 50, fatG: 20, source: .manual),
        ]
        let foods = MealPlanEngine.foods(customFoods: [], mealHistory: history, now: now)
        XCTAssertEqual(foods.count, 1, "Zero-calorie and out-of-window entries are skipped")
        XCTAssertEqual(foods.first?.calories, 300, "The most recent log sets the portion")
        XCTAssertEqual(foods.first?.slots, [.breakfast, .snack])
    }

    func test_foods_customFoodUsesServingAndKeepsDiarySlots() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let custom = CustomFood(
            name: "Skyr",
            per100g: ScannedProduct.Nutriments(calories: 60, proteinG: 11, carbsG: 4, fatG: 0.2, fiberG: nil, sugarsG: nil),
            servingGrams: 150
        )
        let logged = MealEntry(date: now.addingTimeInterval(-3_600), category: .snack, name: "Skyr",
                               calories: 90, proteinG: 17, carbsG: 6, fatG: 0, sourceID: custom.foodID, source: .custom)
        let foods = MealPlanEngine.foods(customFoods: [custom], mealHistory: [logged], now: now)
        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods.first?.calories ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(foods.first?.proteinG ?? 0, 16.5, accuracy: 0.001)
        XCTAssertEqual(foods.first?.slots, [.snack])
        XCTAssertEqual(foods.first?.servingLabel, "150 g")
    }

    func test_plannedMealEntry_scalesMacrosAndComponents() {
        let component = MealFoodComponent(
            id: "custom:x", name: "X", grams: 100, servingGrams: 100, servingLabel: nil,
            per100g: ScannedProduct.Nutriments(calories: 200, proteinG: 20, carbsG: 10, fatG: 5, fiberG: nil, sugarsG: nil),
            sourceID: "custom:x"
        )
        let base = MealPlanEngine.Food(
            id: "custom:x", name: "X", calories: 200, proteinG: 20, carbsG: 10, fatG: 5,
            slots: [], source: .custom, sourceID: "custom:x", components: [component], servingLabel: "100 g"
        )
        let meal = MealPlanEngine.PlannedMeal(slot: .dinner, food: base, portion: 1.5)
        let entry = meal.entry(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entry.category, .dinner)
        XCTAssertEqual(entry.calories, 300)
        XCTAssertEqual(entry.proteinG, 30)
        XCTAssertEqual(entry.components?.first?.grams, 150)
        XCTAssertEqual(entry.sourceID, "custom:x")
    }
}
