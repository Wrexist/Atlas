import XCTest
@testable import Peptide

final class NutritionFactsEngineTests: XCTestCase {
    private typealias Engine = NutritionFactsEngine

    private let yoghurt = ScannedProduct.Nutriments(
        calories: 122, proteinG: 4.3, carbsG: 4.2, fatG: 10, fiberG: 0, sugarsG: 4.2,
        micros: Micronutrients(sodiumMg: 52, potassiumMg: 150, saturatedFatG: 6.6, cholesterolMg: 30)
    )

    private func component(_ id: String, grams: Double, per100g: ScannedProduct.Nutriments) -> MealFoodComponent {
        MealFoodComponent(id: id, name: id, grams: grams, servingGrams: nil, servingLabel: nil, per100g: per100g)
    }

    func test_amount_scalesPer100gToThePortion() throws {
        XCTAssertEqual(try XCTUnwrap(Engine.amount(.saturatedFat, per100g: yoghurt, grams: 150)), 9.9, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(Engine.amount(.sodium, per100g: yoghurt, grams: 150)), 78, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(Engine.amount(.carbs, per100g: yoghurt, grams: 50)), 2.1, accuracy: 0.0001)
    }

    func test_unsaturatedFat_whenNotStated_isFatMinusSaturated() throws {
        XCTAssertEqual(try XCTUnwrap(Engine.per100g(.unsaturatedFat, in: yoghurt)), 3.4, accuracy: 0.0001)
    }

    func test_unsaturatedFat_whenStated_winsOverTheDerivedValue() {
        var stated = yoghurt
        stated.micros?.unsaturatedFatG = 3
        XCTAssertEqual(Engine.per100g(.unsaturatedFat, in: stated), 3)
    }

    func test_saturatedFat_aboveTotalFat_isUnknown_andSoIsTheDerivedUnsaturated() {
        let slip = ScannedProduct.Nutriments(
            calories: 50, proteinG: 1, carbsG: 1, fatG: 2, fiberG: nil, sugarsG: nil,
            micros: Micronutrients(saturatedFatG: 20)
        )
        XCTAssertNil(Engine.per100g(.saturatedFat, in: slip))
        XCTAssertNil(Engine.per100g(.unsaturatedFat, in: slip))
    }

    func test_statedUnsaturated_overrunningTheFat_fallsBackToTheDerivedValue() throws {
        var mixed = yoghurt
        mixed.micros?.unsaturatedFatG = 8
        XCTAssertEqual(try XCTUnwrap(Engine.per100g(.unsaturatedFat, in: mixed)), 3.4, accuracy: 0.0001)
    }

    func test_filling_keepsStatedValues_andTakesOnlyTheGaps() {
        let label = Micronutrients(sodiumMg: 52, saturatedFatG: 6.6)
        let estimate = Micronutrients(sodiumMg: 90, potassiumMg: 140, saturatedFatG: 5, cholesterolMg: 25)
        let filled = label.filling(from: estimate)
        XCTAssertEqual(filled.sodiumMg, 52)
        XCTAssertEqual(filled.saturatedFatG, 6.6)
        XCTAssertEqual(filled.potassiumMg, 140)
        XCTAssertEqual(filled.cholesterolMg, 25)
        XCTAssertEqual(label.filling(from: nil), label)
    }

    func test_missingNutrient_isUnknown_notZero() {
        XCTAssertNil(Engine.amount(.iron, per100g: yoghurt, grams: 150))
        XCTAssertNil(Engine.amount(.calcium, per100g: .zero, grams: 100))
    }

    func test_zeroOrInvalidGrams_isUnknown() {
        XCTAssertNil(Engine.amount(.protein, per100g: yoghurt, grams: 0))
        XCTAssertNil(Engine.amount(.protein, per100g: yoghurt, grams: .nan))
    }

    func test_mealTotal_sumsEveryFood() throws {
        let foods = [component("a", grams: 150, per100g: yoghurt), component("b", grams: 100, per100g: yoghurt)]
        XCTAssertEqual(try XCTUnwrap(Engine.amount(.cholesterol, in: foods)), 75, accuracy: 0.0001)
    }

    func test_mealTotal_withOneFoodMissingTheNutrient_isUnknown() {
        let plain = ScannedProduct.Nutriments(calories: 100, proteinG: 1, carbsG: 20, fatG: 1, fiberG: nil, sugarsG: nil)
        let foods = [component("a", grams: 150, per100g: yoghurt), component("b", grams: 100, per100g: plain)]
        XCTAssertNil(Engine.amount(.sodium, in: foods), "a partial sum would read low")
        XCTAssertNotNil(Engine.amount(.protein, in: foods))
    }

    func test_formatted_usesOneDecimalBelowTen_andWholeNumbersAbove() {
        let comma = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(Engine.formatted(0.44, unit: .grams), "0\(comma)4 g")
        XCTAssertEqual(Engine.formatted(412.3, unit: .milligrams), "412 mg")
        XCTAssertEqual(Engine.formatted(3, unit: .micrograms), "3 µg")
    }

    func test_halfwayScaledValue_roundsUp() {
        let comma = Locale.current.decimalSeparator ?? "."
        let protein = Engine.amount(.protein, per100g: yoghurt, grams: 150) ?? 0
        XCTAssertEqual(Engine.formatted(protein, unit: .grams), "6\(comma)5 g", "4.3 × 1.5 is 6.45")
        XCTAssertEqual(Engine.formatted(183.4, unit: .kilocalories), "183 kcal")
    }

    func test_isEstimate_onlyForDerivedUnsaturatedFat() {
        XCTAssertTrue(Engine.isEstimate(.unsaturatedFat, in: yoghurt))
        XCTAssertFalse(Engine.isEstimate(.saturatedFat, in: yoghurt))
        var stated = yoghurt
        stated.micros?.unsaturatedFatG = 3
        XCTAssertFalse(Engine.isEstimate(.unsaturatedFat, in: stated))
    }

    func test_groups_coverEveryNutrientOnce() {
        let listed = Engine.groups.flatMap { [$0.total].compactMap { $0 } + $0.parts }
        XCTAssertEqual(listed.count, Set(listed).count)
        XCTAssertEqual(Set(listed), Set(Engine.Nutrient.allCases))
    }

    func test_oldStoredNutriments_withoutFatBreakdown_stillDecode() throws {
        let json = #"{"calories":100,"proteinG":1,"carbsG":2,"fatG":3,"micros":{"sodiumMg":40}}"#
        let decoded = try JSONDecoder().decode(ScannedProduct.Nutriments.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.micros?.sodiumMg, 40)
        XCTAssertNil(decoded.micros?.saturatedFatG)
    }
}
