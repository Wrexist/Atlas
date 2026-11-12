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
}
