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
}
