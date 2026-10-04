import XCTest
@testable import Peptide

final class FoodPortionInputTests: XCTestCase {
    func testAcceptsExactAmountsAndBothDecimalKeyboards() {
        XCTAssertEqual(FoodPortionInput.grams("175"), 175)
        XCTAssertEqual(FoodPortionInput.grams(" 125,5 "), 125.5)
        XCTAssertEqual(FoodPortionInput.grams("125.5"), 125.5)
        XCTAssertEqual(FoodPortionInput.grams("5"), 5)
        XCTAssertEqual(FoodPortionInput.grams("2000"), 2000)
    }

    func testRejectsInvalidPartialAndOutOfRangeInput() {
        for value in ["", " ", "0", "4.99", "2000.1", "-10", "nan", "inf", "1e3",
                      "10g", "125.", "1,250.5", "1 250", "1.2.3"] {
            XCTAssertNil(FoodPortionInput.grams(value), value)
        }
    }
}
