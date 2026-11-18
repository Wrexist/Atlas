import XCTest
@testable import Peptide

final class RecipeStepEngineTests: XCTestCase {

    // MARK: - Timers

    func test_timers_swedishNumberWord_readsMinutes() {
        let timers = RecipeStepEngine.timers(in: "Blanda ströbröd och mjölk och låt svälla i fem minuter.")
        XCTAssertEqual(timers.map(\.seconds), [300])
    }

    func test_timers_range_usesShortEnd() {
        let timers = RecipeStepEngine.timers(in: "Pour in the cream and simmer for 8–10 minutes.")
        XCTAssertEqual(timers.map(\.seconds), [480])
    }

    func test_timers_twoWaitsInOneStep_returnsBothInOrder() {
        let timers = RecipeStepEngine.timers(in: "Sear the steak 2–3 minutes per side and rest for 5 minutes.")
        XCTAssertEqual(timers.map(\.seconds), [120, 300])
    }

    func test_timers_hours_convertToSeconds() {
        XCTAssertEqual(RecipeStepEngine.timers(in: "Låt gryta puttra i 1 timme.").map(\.seconds), [3600])
    }

    func test_timers_temperatureAndOvernight_giveNoTimer() {
        XCTAssertTrue(RecipeStepEngine.timers(in: "Sätt ugnen på 200 °C.").isEmpty)
        XCTAssertTrue(RecipeStepEngine.timers(in: "Ställ i kylen över natten.").isEmpty)
    }

    func test_timers_halfHourFraction_readsBothLanguages() {
        XCTAssertEqual(RecipeStepEngine.timers(in: "Cover and simmer gently for 1½ hours until tender.").map(\.seconds), [5400])
        XCTAssertEqual(RecipeStepEngine.timers(in: "Lägg på lock och låt puttra i 1 ½ timme tills köttet är mört.").map(\.seconds), [5400])
        XCTAssertEqual(RecipeStepEngine.timers(in: "Rest for ½ hour.").map(\.seconds), [1800])
    }

    // MARK: - Ingredients

    func test_ingredients_swedishInflectedAndCompound_match() {
        let names = ["Kycklingbröst", "Fullkornsris", "Babyspenat", "Morötter"]
        let step = "Stek kycklingen, rör ner spenaten i riset och riv moroten."
        XCTAssertEqual(RecipeStepEngine.ingredientIndices(in: step, names: names, swedish: true), [0, 1, 2, 3])
    }

    func test_ingredients_unmentioned_areLeftOut() {
        let names = ["Potatis", "Ströbröd", "Mellanmjölk", "Nötfärs 10 %"]
        let step = "Koka potatisen i saltat vatten. Blanda ströbröd och mjölk."
        XCTAssertEqual(RecipeStepEngine.ingredientIndices(in: step, names: names, swedish: true), [0, 1, 2])
    }

    func test_ingredients_cookingVerb_doesNotMatchIngredient() {
        let names = ["Chicken breast", "Brown rice", "Chickpeas"]
        let step = "Add cubed chicken and brown it."
        XCTAssertEqual(RecipeStepEngine.ingredientIndices(in: step, names: names, swedish: false), [0])
    }

    func test_ingredients_exactWordAndPartialCompound_doNotPullInNeighbours() {
        let names = ["Lök", "Vitlök", "Färsk ingefära", "Nötfärs", "Champinjoner"]
        let step = "Fräs lök och rör ner färsen."
        XCTAssertEqual(RecipeStepEngine.ingredientIndices(in: step, names: names, swedish: true), [0, 3])
    }

    func test_ingredients_englishWordPrefix_doesNotMatch() {
        let names = ["Butter", "Potatoes"]
        let step = "Pack with the potatoes, but let them cool first."
        XCTAssertEqual(RecipeStepEngine.ingredientIndices(in: step, names: names, swedish: false), [1])
    }

    func test_steps_ingredientMentionedAgain_isListedOnlyOnFirstUse() throws {
        let recipe = try XCTUnwrap(RecipeLibraryEngine.bundled.first { $0.id == "prep-meatballs-cream-sauce" })
        let steps = RecipeStepEngine.steps(for: recipe, servings: recipe.servings, locale: Locale(identifier: "en"))
        let names = steps.flatMap(\.ingredients).map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(try XCTUnwrap(steps.first).ingredients.map(\.name).contains("Potatoes"))
        XCTAssertFalse(try XCTUnwrap(steps.last).ingredients.map(\.name).contains("Potatoes"))
    }

    func test_steps_scaleAmountsWithServings() throws {
        let recipe = try XCTUnwrap(RecipeLibraryEngine.bundled.first { recipe in
            recipe.steps.contains { !RecipeStepEngine.ingredientIndices(in: $0, names: recipe.ingredients.map(\.name), swedish: false).isEmpty }
        })
        let english = Locale(identifier: "en")
        let one = RecipeStepEngine.steps(for: recipe, servings: 1, locale: english)
        let two = RecipeStepEngine.steps(for: recipe, servings: 2, locale: english)
        let firstOne = try XCTUnwrap(one.flatMap(\.ingredients).first)
        let firstTwo = try XCTUnwrap(two.flatMap(\.ingredients).first)
        XCTAssertEqual(firstOne.name, firstTwo.name)
        XCTAssertGreaterThan(firstTwo.grams, firstOne.grams)
        XCTAssertEqual(one.map(\.id), Array(0..<recipe.steps.count))
    }

    // MARK: - Timer labels

    func test_clock_formatsMinutesAndHours() {
        XCTAssertEqual(CookingTimers.clock(245), "4:05")
        XCTAssertEqual(CookingTimers.clock(3750), "1:02:30")
        XCTAssertEqual(CookingTimers.clock(-3), "0:00")
    }

    private func ingredientsByStep(_ id: String) throws -> [[String]] {
        let recipe = try XCTUnwrap(RecipeLibraryEngine.bundled.first { $0.id == id })
        return RecipeStepEngine.steps(for: recipe, servings: recipe.servings, locale: Locale(identifier: "en"))
            .map { $0.ingredients.map(\.name) }
    }

    func test_steps_cookingWater_leavesTheCreamForThePourStep() throws {
        let steps = try ingredientsByStep("prep-creamy-shrimp-pasta")
        XCTAssertFalse(steps[0].contains("Cooking cream 15%"))
        XCTAssertTrue(steps[1].contains("Cooking cream 15%"))
    }

    func test_steps_burgerSauce_leavesTheBunsForTheToastStep() throws {
        let steps = try ingredientsByStep("prep-burgers-fries-burger-sauce")
        XCTAssertFalse(steps[3].contains("Burger bun"))
        XCTAssertTrue(steps[4].contains("Burger bun"))
    }

    func test_steps_olives_leaveTheOliveOilForTheDressing() throws {
        let steps = try ingredientsByStep("tuna-nicoise")
        XCTAssertTrue(steps[2].contains("Olives"))
        XCTAssertFalse(steps[2].contains("Olive oil"))
        XCTAssertTrue(steps[3].contains("Olive oil"))
    }
}
