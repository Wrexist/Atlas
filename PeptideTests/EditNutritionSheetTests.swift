import XCTest
@testable import Peptide

final class EditNutritionSheetTests: XCTestCase {

    private var yoghurt: LoggableMeal {
        let component = MealFoodComponent(
            id: "7310865000001", name: "Yoghurt", grams: 200, servingGrams: nil, servingLabel: nil,
            per100g: ScannedProduct.Nutriments(calories: 60, proteinG: 4, carbsG: 7, fatG: 2, fiberG: 1.5, sugarsG: 6,
                                               micros: Micronutrients(calciumMg: 120)),
            sourceID: "7310865000001"
        )
        return LoggableMeal(calories: 120, proteinG: 8, carbsG: 14, fatG: 4, components: [component])
    }

    func test_correctCaloriesOnly_keepsFibreSugarAndMicros() throws {
        let corrected = EditNutritionSheet.corrected(yoghurt, calories: 150, proteinG: 8, carbsG: 14, fatG: 4)
        let per100g = try XCTUnwrap(corrected.components?.first?.per100g)
        XCTAssertEqual(per100g.calories, 75, accuracy: 0.001)
        XCTAssertEqual(per100g.fiberG, 1.5)
        XCTAssertEqual(per100g.sugarsG, 6)
        XCTAssertEqual(per100g.micros?.calciumMg, 120)
    }
}
