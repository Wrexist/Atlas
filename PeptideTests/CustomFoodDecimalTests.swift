import XCTest
@testable import Peptide

/// The custom-food editor shows stored values as text and parses them
/// back on save, so the two have to agree in every locale.
@MainActor
final class CustomFoodDecimalTests: XCTestCase {

    private let german = Locale(identifier: "de_DE")
    private let us = Locale(identifier: "en_US")

    func test_roundTrip_dotGroupingLocale_keepsValue() throws {
        let text = CustomFoodEditorSheet.formatDecimal(1.5, locale: german)
        XCTAssertEqual(try XCTUnwrap(CustomFoodEditorSheet.parseDecimal(text, locale: german)), 1.5, accuracy: 0.0001)
    }

    func test_parse_pastedDotDecimalInDotGroupingLocale_isNotScaledByTen() throws {
        XCTAssertEqual(try XCTUnwrap(CustomFoodEditorSheet.parseDecimal("1.5", locale: german)), 1.5, accuracy: 0.0001)
    }

    func test_parse_commaDecimalInCommaLocale_readsDecimal() throws {
        XCTAssertEqual(try XCTUnwrap(CustomFoodEditorSheet.parseDecimal("3,4", locale: german)), 3.4, accuracy: 0.0001)
    }

    func test_format_floatNoise_roundsToTwoDecimals() {
        XCTAssertEqual(CustomFoodEditorSheet.formatDecimal(0.1 + 0.2, locale: us), "0.3")
    }

    func test_format_largeWholeNumber_hasNoGroupingSeparator() {
        let text = CustomFoodEditorSheet.formatDecimal(1200, locale: german)
        XCTAssertEqual(text, "1200")
        XCTAssertEqual(CustomFoodEditorSheet.parseDecimal(text, locale: german), 1200)
    }

    private func problem(calories: Double? = 100, protein: Double? = 5, carbs: Double? = 20, fat: Double? = 1,
                         fiber: Double? = nil, sugars: Double? = nil,
                         servingGrams: Double? = nil) -> CustomFoodEditorSheet.InputProblem? {
        CustomFoodEditorSheet.inputProblem(calories: calories, protein: protein, carbs: carbs, fat: fat,
                                           fiber: fiber, sugars: sugars, servingGrams: servingGrams)
    }

    func test_inputProblem_plausibleFood_isValid() {
        XCTAssertNil(problem(fiber: 3, sugars: 10, servingGrams: 250))
    }

    func test_inputProblem_hugeServing_isOutOfRange() {
        XCTAssertEqual(problem(servingGrams: 10_000), .servingOutOfRange)
    }

    func test_inputProblem_fiberOver100g_isRejected() {
        XCTAssertEqual(problem(fiber: 500), .fiberOrSugarsOver100g)
    }

    func test_inputProblem_sugarsAboveCarbs_stillSaves() {
        XCTAssertNil(problem(carbs: 10, sugars: 12))
    }

    func test_sugarsExceedCarbs_bothEntered_warns() {
        XCTAssertTrue(CustomFoodEditorSheet.sugarsExceedCarbs(carbs: 10, sugars: 12))
        XCTAssertFalse(CustomFoodEditorSheet.sugarsExceedCarbs(carbs: 12, sugars: 10))
    }

    func test_sugarsExceedCarbs_carbsBlank_doesNotWarn() {
        XCTAssertFalse(CustomFoodEditorSheet.sugarsExceedCarbs(carbs: nil, sugars: 5))
    }
}
