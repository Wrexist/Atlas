import XCTest
@testable import Peptide

final class FoodLibraryLogicTests: XCTestCase {
    private func food(_ name: String = "Oats") -> CustomFood {
        CustomFood(name: name, per100g: .init(calories: 380, proteinG: 13,
            carbsG: 67, fatG: 7, fiberG: 10, sugarsG: 1))
    }

    func testRecipeRequiresEveryIngredientAndValidPortion() {
        let oats = food()
        let valid = Recipe.Component(foodID: oats.foodID, cachedName: "Oats", portion: .grams(80))
        let missing = Recipe.Component(foodID: "custom:missing", cachedName: "Missing", portion: .grams(100))
        let review = RecipeDataLogic.review(for: Recipe(name: "Bowl", components: [valid, missing]), customFoods: [oats])
        XCTAssertNil(review.totals)
        XCTAssertEqual(review.unresolved.map(\.id), [missing.id])
        XCTAssertNil(RecipeDataLogic.review(for: Recipe(name: "Empty"), customFoods: [oats]).totals)
        XCTAssertEqual(RecipeDataLogic.review(for: Recipe(name: "Valid", components: [valid]), customFoods: [oats]).totals?.calories, 304)
        let invalid = Recipe.Component(foodID: oats.foodID, cachedName: "Oats", portion: .grams(-10))
        XCTAssertNil(RecipeDataLogic.review(for: Recipe(name: "Invalid", components: [invalid]), customFoods: [oats]).totals)
        XCTAssertNil(oats.toScannedProduct().loggable(for: .grams(.infinity)))
        XCTAssertNil(oats.toScannedProduct().loggable(for: .grams(.nan)))
    }

    func testSearchRankingDeduplicatesAndPreservesTies() {
        let exact = food("Oats").toScannedProduct()
        let prefix = food("Oats rolled").toScannedProduct()
        let other = food("Rice").toScannedProduct()
        let another = food("Bread").toScannedProduct()
        XCTAssertEqual(FoodLibraryLogic.ranked([other, prefix, exact, exact, another], query: "OATS").map(\.barcode),
                       [exact, prefix, other, another].map(\.barcode))
        XCTAssertEqual(FoodLibraryLogic.ranked([other, exact, other], query: "").map(\.barcode), [other.barcode, exact.barcode])
    }

    func testRememberedPortionUsesLatestValidSnapshot() throws {
        let product = food().toScannedProduct()
        let old = MealEntry(loggable: try XCTUnwrap(product.loggable(for: .grams(80))), name: product.name,
                            category: .breakfast, source: .custom, sourceID: product.barcode, date: Date(timeIntervalSince1970: 100))
        let newer = MealEntry(loggable: try XCTUnwrap(product.loggable(for: .grams(120))), name: product.name,
                              category: .breakfast, source: .custom, sourceID: product.barcode, date: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(FoodLibraryLogic.previousGrams(for: product, history: [newer, old]), 120)
        XCTAssertNil(FoodLibraryLogic.previousGrams(for: food("Rice").toScannedProduct(), history: [newer]))
        XCTAssertNil(FoodLibraryLogic.previousGrams(for: product, history: []))
    }

    @MainActor
    func testRecipeSaveFailureDoesNotLogPartialOrVolatileSuccess() throws {
        let repo = SwiftDataRepository.shared
        repo.configureForTesting()
        let store = DataStore(seedSampleData: false)
        defer {
            repo.forceCommitFailureForTesting = false
            store.flushPendingSave()
            DataStore.current = nil
            repo.configureForTesting()
        }
        store.profile.healthKitNutritionEnabled = false
        let oats = food()
        store.profile.customFoods = [oats]
        store.flushPendingSave()
        let recipe = Recipe(name: "Oats", components: [.init(foodID: oats.foodID, cachedName: "Oats", portion: .grams(80))])
        let before = store.profile.mealHistory.count
        repo.forceCommitFailureForTesting = true
        XCTAssertNil(store.logRecipe(recipe))
        XCTAssertEqual(store.profile.mealHistory.count, before)
        repo.forceCommitFailureForTesting = false
        XCTAssertNotNil(store.logRecipe(recipe))
        XCTAssertEqual(store.profile.mealHistory.count, before + 1)
        store.profile.customFoods = []
        XCTAssertNil(store.logRecipe(recipe))
        XCTAssertEqual(store.profile.mealHistory.count, before + 1)
    }
}
