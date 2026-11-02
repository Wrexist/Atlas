import XCTest
@testable import Peptide

final class MicronutrientEngineTests: XCTestCase {

    /// Fixed instant; the engine never reads the date, so no calendar is involved.
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func food(_ grams: Double, _ micros: Micronutrients?) -> MealFoodComponent {
        MealFoodComponent(
            id: UUID().uuidString, name: "Food", grams: grams,
            per100g: .init(calories: 100, proteinG: 5, carbsG: 10, fatG: 3, fiberG: nil, sugarsG: nil, micros: micros)
        )
    }

    private func entry(_ components: [MealFoodComponent]?) -> MealEntry {
        MealEntry(date: day, category: .lunch, name: "Meal", calories: 100, proteinG: 5, carbsG: 10, fatG: 3,
                  source: .openFoodFacts, components: components)
    }

    func test_intake_scalesPer100gByPortionAndSumsAcrossMeals() throws {
        let entries = [
            entry([food(200, Micronutrients(ironMg: 2))]),
            entry([food(50, Micronutrients(ironMg: 4)), food(100, Micronutrients(ironMg: 1.5))]),
        ]
        let intake = MicronutrientEngine.intake(of: .iron, in: entries)
        XCTAssertEqual(try XCTUnwrap(intake.total), 4 + 2 + 1.5, accuracy: 0.0001)
        XCTAssertEqual(intake.missing, 0)
        XCTAssertEqual(try XCTUnwrap(intake.fraction), 7.5 / 14, accuracy: 0.0001)
    }

    func test_intake_foodsWithoutTheNutrient_countAsMissingNotZero() {
        let entries = [
            entry([food(100, Micronutrients(calciumMg: 120)), food(100, nil)]),
            entry(nil),
            entry([food(100, Micronutrients(ironMg: 1))]),
        ]
        let intake = MicronutrientEngine.intake(of: .calcium, in: entries)
        XCTAssertEqual(intake.total, 120)
        XCTAssertEqual(intake.missing, 3, "a food without micros, a legacy meal, a food without calcium")
    }

    func test_intake_noFoodStatesIt_hasNoTotalOrFraction() {
        let intake = MicronutrientEngine.intake(of: .vitaminD, in: [entry([food(100, nil)])])
        XCTAssertNil(intake.total)
        XCTAssertNil(intake.fraction)
        XCTAssertFalse(intake.isOverLimit)
    }

    func test_sodium_overTheDailyCeiling_isOverLimit() {
        let entries = [entry([food(500, Micronutrients(sodiumMg: 500))])]
        let intake = MicronutrientEngine.intake(of: .sodium, in: entries)
        XCTAssertEqual(intake.total, 2_500)
        XCTAssertTrue(intake.isOverLimit)
    }

    func test_targetNutrients_overTheirReference_areNeverOverLimit() throws {
        let entries = [entry([food(1_000, Micronutrients(calciumMg: 200))])]
        let intake = MicronutrientEngine.intake(of: .calcium, in: entries)
        XCTAssertGreaterThan(try XCTUnwrap(intake.fraction), 1)
        XCTAssertFalse(intake.isOverLimit)
    }

    func test_dailyIntakes_coverEveryNutrientInDisplayOrder() {
        let intakes = MicronutrientEngine.dailyIntakes([])
        XCTAssertEqual(intakes.map(\.nutrient), [.sodium, .potassium, .iron, .calcium, .vitaminD, .vitaminB12])
        XCTAssertTrue(intakes.allSatisfy { $0.total == nil && $0.missing == 0 })
    }

    func test_referenceValues_useLabelUnits() {
        XCTAssertEqual(MicronutrientEngine.Nutrient.sodium.dailyReference, 2_000)
        XCTAssertEqual(MicronutrientEngine.Nutrient.vitaminD.unit, .micrograms)
        XCTAssertEqual(MicronutrientEngine.Nutrient.vitaminB12.dailyReference, 4)
        XCTAssertEqual(MicronutrientEngine.Nutrient.potassium.unit, .milligrams)
    }

    func test_storedMealWithoutMicros_decodesAsUnknown() throws {
        let json = #"{"calories":100,"proteinG":5,"carbsG":10,"fatG":3,"fiberG":2}"#
        let nutriments = try JSONDecoder().decode(ScannedProduct.Nutriments.self, from: Data(json.utf8))
        XCTAssertNil(nutriments.micros)
        XCTAssertEqual(nutriments.fiberG, 2)
    }

    func test_emptyMicronutrients_collapseToNil() {
        XCTAssertNil(Micronutrients().nonEmpty)
        XCTAssertEqual(Micronutrients(ironMg: 0).nonEmpty?.ironMg, 0, "a stated zero is data")
    }
}
