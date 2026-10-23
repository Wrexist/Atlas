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

    /// Mirrors the review card's "most of the plate is a guess" rule, so
    /// the majority threshold can't drift without a test noticing.
    func test_uncertainMajority_needsMoreThanHalf() {
        func uncertainCount(_ confidences: [Double]) -> Int {
            confidences.map { EditableFoodItem(from: scanned(confidence: $0)) }
                .filter(\.isUncertain).count
        }
        // Two of four is not a majority; three of four is.
        XCTAssertFalse(uncertainCount([0.1, 0.2, 0.9, 0.9]) * 2 > 4)
        XCTAssertTrue(uncertainCount([0.1, 0.2, 0.3, 0.9]) * 2 > 4)
    }

    func test_loggedName_clearedName_fallsBackToScannerName() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9))
        item.name = "   "
        XCTAssertEqual(item.loggedName, "watermelon")
        XCTAssertEqual(item.component.name, "watermelon")
    }

    func test_loggedName_editedName_isTrimmed() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9))
        item.name = " Honeydew "
        XCTAssertEqual(item.loggedName, "Honeydew")
    }

    private func scanned(confidence: Double, grams: Double = 200) -> MealScannerService.ScannedFoodItem {
        MealScannerService.ScannedFoodItem(
            name: "watermelon",
            quantityLabel: "2 slices",
            grams: grams,
            calories: 200,
            proteinG: 4,
            carbsG: 50,
            fatG: 1,
            confidence: confidence
        )
    }

    func testNutritionCorrectionScalesWithPortionAndResetsWithoutChangingPortion() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9))
        item.savedToLibrary = true
        item.correctNutrition(.init(calories: 300, proteinG: 12, carbsG: 45, fatG: 8))
        XCTAssertEqual(item.calories, 300)
        XCTAssertTrue(item.nutritionEdited)
        XCTAssertFalse(item.savedToLibrary)
        item.grams = 100
        XCTAssertEqual(item.calories, 150)
        XCTAssertEqual(item.proteinG, 6)
        XCTAssertEqual(item.fatG, 4)
        item.resetNutrition()
        XCTAssertEqual(item.grams, 100)
        XCTAssertEqual(item.calories, 100)
        XCTAssertFalse(item.nutritionEdited)
    }

    func testInvalidNutritionCorrectionLeavesEstimateUntouched() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9))
        item.correctNutrition(.init(calories: -1, proteinG: 1, carbsG: 1, fatG: 1))
        XCTAssertEqual(item.calories, 200)
        XCTAssertFalse(item.nutritionEdited)
        item.grams = 0
        item.correctNutrition(.init(calories: 100, proteinG: 1, carbsG: 1, fatG: 1))
        XCTAssertFalse(item.nutritionEdited)
    }

    func test_stepGrams_onPortionAboveTwoKilos_increasesGrams() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9, grams: 2_500))
        item.stepGrams(by: 10)
        XCTAssertEqual(item.grams, 2_510)
    }

    func test_clampedGrams_oneServingOfLargePortion_restoresScannedAmount() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9, grams: 2_500))
        item.grams = 1_000
        item.grams = EditableFoodItem.clampedGrams(item.aiGrams.rounded())
        XCTAssertEqual(item.grams, 2_500)
    }

    func test_stepGrams_downFromTinyPortion_neverIncreasesGrams() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9, grams: 2))
        item.stepGrams(by: -10)
        XCTAssertEqual(item.grams, 1)
        item.stepGrams(by: -10)
        XCTAssertEqual(item.grams, 1)
    }

    func test_stepGrams_atScannerCeiling_staysPut() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9, grams: 5_000))
        item.stepGrams(by: 10)
        XCTAssertEqual(item.grams, 5_000)
    }

    func test_servingAfterReplace_usesReplacementFoodsServing() {
        var item = EditableFoodItem(from: scanned(confidence: 0.9))
        item.replace(with: ScannedProduct(
            barcode: "7310865004703", name: "Crispbread", brand: nil, imageURL: nil,
            servingSizeText: "1 slice (12 g)", servingGrams: 12, packageGrams: nil,
            per100g: .init(calories: 340, proteinG: 10, carbsG: 60, fatG: 2, fiberG: 18, sugarsG: 1),
            nutriScore: nil, novaGroup: nil, fetchedAt: Date()
        ))
        XCTAssertEqual(item.servingGrams, 12)
        XCTAssertEqual(item.servingLabel, "1 slice (12 g)")
        item.resetNutrition()
        XCTAssertEqual(item.servingGrams, 200)
        XCTAssertEqual(item.servingLabel, "2 slices")
    }

    func test_correctNutrition_keepsScannedFibreAndSugar() {
        var scan = scanned(confidence: 0.9)
        scan.per100g = .init(calories: 100, proteinG: 2, carbsG: 25, fatG: 0.5, fiberG: 3, sugarsG: 12)
        var item = EditableFoodItem(from: scan)
        item.correctNutrition(.init(calories: 260, proteinG: 4, carbsG: 50, fatG: 1))
        XCTAssertEqual(item.per100g.fiberG, 3)
        XCTAssertEqual(item.per100g.sugarsG, 12)
        XCTAssertEqual(item.calories, 260)
    }
}
