import XCTest
@testable import Peptide

final class NutritionTargetsEditorTests: XCTestCase {

    func test_liveValue_nineteenDigitFat_yieldsFiniteMacroCalories() {
        let fat = NutritionTargetsEditor.liveValue("2000000000000000000")
        let (kcal, overflow) = fat.multipliedReportingOverflow(by: 9)
        XCTAssertFalse(overflow)
        XCTAssertEqual(kcal, 900_000)
    }

    func test_liveValue_blankOrNegative_readsAsZero() {
        XCTAssertEqual(NutritionTargetsEditor.liveValue(""), 0)
        XCTAssertEqual(NutritionTargetsEditor.liveValue("-40"), 0)
    }

    func test_liveValue_ordinaryEntry_isUnchanged() {
        XCTAssertEqual(NutritionTargetsEditor.liveValue("2350"), 2350)
    }
}
