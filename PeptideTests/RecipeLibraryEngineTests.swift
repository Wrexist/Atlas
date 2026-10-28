import XCTest
@testable import Peptide

final class RecipeLibraryEngineTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private let english = Locale(identifier: "en")

    /// The bundled file, from the app bundle when the tests are hosted and
    /// from the source tree otherwise.
    private func bundledLibrary() throws -> [LibraryRecipe] {
        if let url = Bundle.main.url(forResource: "recipe-library", withExtension: "json") {
            return try RecipeLibraryEngine.decode(Data(contentsOf: url))
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Peptide/Resources/recipe-library.json")
        return try RecipeLibraryEngine.decode(Data(contentsOf: url))
    }

    private func ingredient(_ key: String, sv: String? = nil, grams: Double = 100) -> LibraryRecipe.Ingredient {
        LibraryRecipe.Ingredient(name: key.capitalized, nameSV: sv ?? key, grams: grams, pantryKey: key)
    }

    private func recipe(
        _ id: String,
        category: MealCategory = .lunch,
        calories: Int = 500,
        protein: Double = 20,
        fiber: Double = 4,
        ingredients: [LibraryRecipe.Ingredient]? = nil,
        tags: [String] = [],
        micros: LibraryRecipe.Micros = LibraryRecipe.Micros(
            sodiumMg: 0, potassiumMg: 0, ironMg: 0, calciumMg: 0, vitaminDUg: 0, vitaminB12Ug: 0
        )
    ) -> LibraryRecipe {
        LibraryRecipe(
            id: id,
            name: id.capitalized,
            nameSV: "\(id) sv",
            category: category,
            mealPrep: false,
            minutes: 20,
            servings: 2,
            fridgeDays: nil,
            tags: tags,
            ingredients: ingredients ?? [ingredient("rice"), ingredient("tomato")],
            steps: ["One", "Two", "Three"],
            stepsSV: ["Ett", "Två", "Tre"],
            calories: calories,
            proteinG: protein,
            carbsG: 50,
            fatG: 10,
            fiberG: fiber,
            micros: micros,
            image: "recipe-\(id)"
        )
    }

    private func context(
        hour: Int = 13,
        favorites: [String] = [],
        needs: RecipeLibraryEngine.Needs? = nil,
        recent: Set<String> = [],
        pantry: Set<String> = []
    ) -> RecipeLibraryEngine.Context {
        RecipeLibraryEngine.Context(
            favoriteFoodNames: favorites,
            needs: needs,
            now: date(hour: hour),
            calendar: calendar,
            recentMealNames: recent,
            pantry: pantry
        )
    }

    private func score(_ recipe: LibraryRecipe, _ context: RecipeLibraryEngine.Context) -> Double {
        RecipeLibraryEngine.recommendation(for: recipe, context: context).score
    }

    // MARK: - Library

    func test_bundledLibrary_decodesWithUniqueIDs() throws {
        let library = try bundledLibrary()
        XCTAssertGreaterThanOrEqual(library.count, 55)
        XCTAssertEqual(Set(library.map(\.id)).count, library.count, "Recipe ids must be unique")
        XCTAssertGreaterThanOrEqual(library.filter(\.mealPrep).count, 15)
        for recipe in library {
            XCTAssertEqual(recipe.image, "recipe-\(recipe.id)")
            XCTAssertFalse(recipe.ingredients.isEmpty, recipe.id)
            XCTAssertTrue((3...6).contains(recipe.steps.count), recipe.id)
            XCTAssertEqual(recipe.steps.count, recipe.stepsSV.count, recipe.id)
            if recipe.mealPrep {
                XCTAssertTrue((4...5).contains(recipe.servings), recipe.id)
                XCTAssertNotNil(recipe.fridgeDays, recipe.id)
            }
            for ingredient in recipe.ingredients {
                XCTAssertEqual(ingredient.pantryKey, ingredient.pantryKey.lowercased(), recipe.id)
            }
        }
    }

    func test_bundledLibrary_caloriesMatchMacrosWithinTenPercent() throws {
        for recipe in try bundledLibrary() {
            let fromMacros = 4 * recipe.proteinG + 4 * recipe.carbsG + 9 * recipe.fatG
            let deviation = abs(Double(recipe.calories) - fromMacros) / fromMacros
            XCTAssertLessThanOrEqual(deviation, 0.10, "\(recipe.id): \(recipe.calories) kcal vs \(Int(fromMacros)) from macros")
        }
    }

    func test_bundledLibrary_hasFishAtLeastTwiceAWeekWorth() throws {
        let library = try bundledLibrary()
        XCTAssertGreaterThanOrEqual(library.filter { $0.tags.contains("fish") }.count, 6)
    }

    // MARK: - Favourites

    func test_favoriteIngredient_boostsRanking() {
        let salmon = recipe("salmon-bowl", ingredients: [ingredient("salmon", sv: "Laxfilé"), ingredient("rice")])
        let chicken = recipe("chicken-bowl", ingredients: [ingredient("chicken breast", sv: "Kycklingbröst"), ingredient("rice")])

        let ranked = RecipeLibraryEngine.recommend([chicken, salmon], context: context(favorites: ["Lax, färsk"]))

        XCTAssertEqual(ranked.first?.recipe.id, "salmon-bowl")
        XCTAssertEqual(ranked.first?.reasons.first, .favorites([salmon.ingredients[0]]))
    }

    func test_favoriteMatching_ignoresFormWordsLikeBreast() {
        let turkey = recipe("turkey", ingredients: [ingredient("turkey breast", sv: "Kalkonbröst")])

        XCTAssertTrue(RecipeLibraryEngine.favoriteIngredients(in: turkey, favoriteNames: ["Chicken breast"]).isEmpty)
        XCTAssertEqual(RecipeLibraryEngine.favoriteIngredients(in: turkey, favoriteNames: ["Kalkon skivad"]).count, 1)
    }

    func test_favoriteFoodNames_resolveCustomFoodsAndLoggedBarcodes() {
        let food = CustomFood(name: "Kvarg vanilj", per100g: .zero)
        let meal = MealEntry(
            date: date(hour: 8), category: .breakfast, name: "Arla Skyr", calories: 100,
            proteinG: 10, carbsG: 4, fatG: 0, sourceID: "7310865000000", source: .openFoodFacts
        )

        let names = RecipeLibraryEngine.favoriteFoodNames(
            favoriteIDs: [food.foodID, "7310865000000"],
            customFoods: [food],
            mealHistory: [meal]
        )

        XCTAssertEqual(Set(names), ["Kvarg vanilj", "Arla Skyr"])
    }

    // MARK: - Today's needs

    func test_proteinNeed_boostsHighProteinRecipeMore() {
        let lean = recipe("lean", calories: 500, protein: 45, tags: ["high-protein"])
        let starchy = recipe("starchy", calories: 500, protein: 10)
        let hungry = context(needs: RecipeLibraryEngine.Needs(remainingCalories: 1200, remainingProteinG: 90))
        let met = context(needs: RecipeLibraryEngine.Needs(remainingCalories: 1200, remainingProteinG: 0))

        let gapWithNeed = score(lean, hungry) - score(starchy, hungry)
        let gapWithoutNeed = score(lean, met) - score(starchy, met)

        XCTAssertGreaterThan(gapWithNeed, gapWithoutNeed)
        XCTAssertEqual(RecipeLibraryEngine.recommend([starchy, lean], context: hungry).first?.recipe.id, "lean")
    }

    func test_overshootingCalories_isPenalised() {
        let small = recipe("small", calories: 400, protein: 30)
        let large = recipe("large", calories: 900, protein: 30)
        let needs = RecipeLibraryEngine.Needs(remainingCalories: 450, remainingProteinG: 30)

        XCTAssertGreaterThan(score(small, context(needs: needs)), score(large, context(needs: needs)))
        XCTAssertLessThan(score(large, context(needs: needs)), score(large, context()))
    }

    func test_fibreNeed_rewardsFibreRichRecipe() {
        let beans = recipe("beans", fiber: 14)
        let plain = recipe("plain", fiber: 2)
        let needs = RecipeLibraryEngine.Needs(remainingCalories: 1500, remainingProteinG: 0, remainingFiberG: 20)

        let ranked = RecipeLibraryEngine.recommend([plain, beans], context: context(needs: needs))

        XCTAssertEqual(ranked.first?.recipe.id, "beans")
        XCTAssertTrue(ranked.first?.reasons.contains(.fiber) ?? false)
    }

    func test_fibreTargetMet_givesFibreRichRecipeNoEdge() {
        let beans = recipe("beans", fiber: 14)
        let plain = recipe("plain", fiber: 2)
        let needs = RecipeLibraryEngine.Needs(remainingCalories: 1500, remainingProteinG: 0, remainingFiberG: 0)
        let ctx = context(needs: needs)

        let beansScore = RecipeLibraryEngine.recommendation(for: beans, context: ctx).score
        let plainScore = RecipeLibraryEngine.recommendation(for: plain, context: ctx).score

        XCTAssertEqual(beansScore, plainScore, accuracy: 0.001)
    }

    func test_lowMicronutrient_rewardsRecipeRichInIt() {
        let ironRich = recipe("lentils", micros: .init(sodiumMg: 0, potassiumMg: 0, ironMg: 6, calciumMg: 0, vitaminDUg: 0, vitaminB12Ug: 0))
        let plain = recipe("plain")
        var needs = RecipeLibraryEngine.Needs(remainingCalories: 1500, remainingProteinG: 0)
        needs.lowMicros = [.iron]

        let ranked = RecipeLibraryEngine.recommend([plain, ironRich], context: context(needs: needs))

        XCTAssertEqual(ranked.first?.recipe.id, "lentils")
        XCTAssertTrue(ranked.first?.reasons.contains(.micro(.iron)) ?? false)
    }

    // MARK: - Time, variety, pantry

    func test_timeOfDay_prefersMatchingCategory() {
        let breakfast = recipe("oats", category: .breakfast)
        let dinner = recipe("stew", category: .dinner)

        XCTAssertEqual(RecipeLibraryEngine.recommend([dinner, breakfast], context: context(hour: 7)).first?.recipe.id, "oats")
        XCTAssertEqual(RecipeLibraryEngine.recommend([breakfast, dinner], context: context(hour: 19)).first?.recipe.id, "stew")
    }

    func test_recentlyEaten_isPenalised() {
        let soup = recipe("soup")
        let salad = recipe("salad")
        let recent = RecipeLibraryEngine.recentMealNames(
            in: [
                MealEntry(date: date(hour: 12, day: 13), category: .lunch, name: "soup sv", calories: 500,
                          proteinG: 20, carbsG: 50, fatG: 10, source: .manual),
                MealEntry(date: date(hour: 12, day: 5), category: .lunch, name: "Salad", calories: 500,
                          proteinG: 20, carbsG: 50, fatG: 10, source: .manual),
            ],
            now: date(hour: 13),
            calendar: calendar
        )

        XCTAssertEqual(recent, ["soup sv"])
        XCTAssertEqual(RecipeLibraryEngine.recommend([soup, salad], context: context(recent: recent)).first?.recipe.id, "salad")
    }

    func test_mostIngredientsAtHome_addsPantryBonus() {
        let stocked = recipe("stocked", ingredients: [ingredient("egg"), ingredient("spinach"), ingredient("tomato")])
        let missing = recipe("missing", ingredients: [ingredient("cod"), ingredient("potato"), ingredient("pea")])

        let ranked = RecipeLibraryEngine.recommend([missing, stocked], context: context(pantry: ["egg", "spinach"]))

        XCTAssertEqual(ranked.first?.recipe.id, "stocked")
        XCTAssertEqual(ranked.first?.reasons.first, .pantry(have: 2, total: 3))
        XCTAssertEqual(RecipeLibraryEngine.pantryCoverage(missing, pantry: ["egg"]).have, 0)
    }

    func test_fewIngredientsAtHome_addsNoBonus() {
        let dish = recipe("dish", ingredients: [ingredient("egg"), ingredient("spinach"), ingredient("tomato")])

        XCTAssertEqual(score(dish, context(pantry: ["egg"])), score(dish, context()))
    }

    func test_ranking_isDeterministicOnTies() {
        let a = recipe("a")
        let b = recipe("b")

        XCTAssertEqual(RecipeLibraryEngine.recommend([b, a], context: context()).map(\.recipe.id), ["a", "b"])
    }

    // MARK: - Reason text

    func test_reasonText_joinsTopTwoReasons() {
        let text = RecipeLibraryEngine.reasonText([.highProtein, .fitsCalories(remaining: 640), .fiber], locale: english)

        XCTAssertTrue(text.contains("640"), text)
        XCTAssertTrue(text.contains(" · "), text)
        XCTAssertEqual(text.components(separatedBy: " · ").count, 2)
    }

    func test_reasonText_namesFavouriteIngredientsInLocale() {
        let salmon = ingredient("salmon", sv: "Lax")
        let broccoli = ingredient("broccoli", sv: "Broccoli")

        let inEnglish = RecipeLibraryEngine.reasonText([.favorites([salmon, broccoli])], locale: english)
        let inSwedish = RecipeLibraryEngine.text(for: .favorites([salmon, broccoli]), locale: Locale(identifier: "sv"))

        XCTAssertTrue(inEnglish.contains("salmon, broccoli"), inEnglish)
        XCTAssertTrue(inSwedish.contains("lax, broccoli"), inSwedish)
    }

    func test_highProteinRecipe_givesReasonWithoutTargets() {
        let lean = recipe("lean", protein: 40, tags: ["high-protein"])

        let reasons = RecipeLibraryEngine.recommendation(for: lean, context: context()).reasons

        XCTAssertEqual(reasons.first, .highProtein)
    }

    // MARK: - Servings and logging

    func test_servings_scaleIngredientGrams() {
        let oats = ingredient("oat", grams: 45)

        XCTAssertEqual(RecipeLibraryEngine.grams(oats, servings: 1), 45)
        XCTAssertEqual(RecipeLibraryEngine.grams(oats, servings: 4), 180)
        XCTAssertEqual(RecipeLibraryEngine.grams(oats, servings: 0), 45)
        XCTAssertEqual(RecipeLibraryEngine.displayGrams(447.5), 450)
        XCTAssertEqual(RecipeLibraryEngine.displayGrams(37.4), 37)
    }

    func test_entry_logsOneServingInTheTimeOfDaySlot() {
        let dish = recipe("bowl", category: .dinner, calories: 520, protein: 41.6, fiber: 9)

        let entry = RecipeLibraryEngine.entry(for: dish, locale: english, at: date(hour: 12), calendar: calendar)

        XCTAssertEqual(entry.category, .lunch)
        XCTAssertEqual(entry.name, "Bowl")
        XCTAssertEqual(entry.calories, 520)
        XCTAssertEqual(entry.proteinG, 42)
        XCTAssertEqual(entry.fiberG ?? 0, 9, accuracy: 0.01)
        XCTAssertEqual(entry.components?.first?.macros?.calories, 520)
    }
}
