import XCTest
@testable import Peptide

/// The scanner has always returned a confidence and the review row has
/// always ignored it, which is how "Tomato slices" on a plate of melon
/// came to look exactly as settled as a barcode lookup. These cover the
/// two things that has to keep doing: carry the number through the
/// transform, and turn it into a flag at the right point.
final class EditableFoodItemTests: XCTestCase {

    func test_init_carriesConfidenceFromTheScannedItem() {
        let item = EditableFoodItem(from: scanned(confidence: 0.42))
        XCTAssertEqual(item.confidence, 0.42, accuracy: 0.0001)
    }

    func test_isUncertain_isTrueBelowTheThreshold() {
        XCTAssertTrue(EditableFoodItem(from: scanned(confidence: 0.35)).isUncertain)
    }

    func test_isUncertain_isFalseAtAndAboveTheThreshold() {
        let threshold = EditableFoodItem.uncertaintyThreshold
        XCTAssertFalse(EditableFoodItem(from: scanned(confidence: threshold)).isUncertain)
        XCTAssertFalse(EditableFoodItem(from: scanned(confidence: 0.95)).isUncertain)
    }

    func test_isUncertain_isTrueForAZeroConfidenceGuess() {
        XCTAssertTrue(EditableFoodItem(from: scanned(confidence: 0)).isUncertain)
    }

    /// Portion maths must be untouched by the new field — the row still
    /// rescales macros off the per-100g basis, not off confidence.
    func test_confidenceDoesNotAffectPortionMaths() {
        var item = EditableFoodItem(from: scanned(confidence: 0.1))
        XCTAssertEqual(item.calories, 200)
        item.grams = 100
        XCTAssertEqual(item.calories, 100)
    }

    private func scanned(confidence: Double) -> MealScannerService.ScannedFoodItem {
        MealScannerService.ScannedFoodItem(
            name: "watermelon",
            quantityLabel: "2 slices",
            grams: 200,
            calories: 200,
            proteinG: 4,
            carbsG: 50,
            fatG: 1,
            confidence: confidence
        )
    }
}
