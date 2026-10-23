import XCTest
@testable import Peptide

final class FoodPictureLinkTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_760_000_000)
    private let packshot = URL(string: "https://images.openfoodfacts.org/images/products/1/front_en.400.jpg")!

    func test_offMeal_exposesItsBarcode() {
        XCTAssertEqual(meal(source: .openFoodFacts, sourceID: "7310865004703").productBarcode, "7310865004703")
    }

    func test_packageReadMeal_hasNoBarcodeToLookUp() {
        XCTAssertNil(meal(source: .openFoodFacts, sourceID: "ai:\(UUID().uuidString)").productBarcode)
    }

    func test_photoMeal_hasNoBarcode() {
        XCTAssertNil(meal(source: .photo, sourceID: nil).productBarcode)
    }

    func test_customFoodMeal_usesTheSavedFoodsPicture() {
        let food = CustomFood(name: "Kvarg", per100g: .init(calories: 60, proteinG: 11, carbsG: 3, fatG: 0.2, fiberG: nil, sugarsG: nil), imageURL: packshot)
        let entry = meal(source: .custom, sourceID: food.foodID)
        XCTAssertEqual(entry.pictureURL(in: [food]), packshot)
    }

    func test_customFoodMeal_whoseFoodWasDeleted_hasNoPicture() {
        let entry = meal(source: .custom, sourceID: "custom:\(UUID().uuidString)")
        XCTAssertNil(entry.pictureURL(in: []))
    }

    func test_barcodeProductSavedToMyFoods_keepsItsPicture() {
        let product = ScannedProduct(
            barcode: "7310865004703", name: "Kvarg", brand: "Arla", imageURL: packshot,
            servingSizeText: nil, servingGrams: nil, packageGrams: 500,
            per100g: .init(calories: 60, proteinG: 11, carbsG: 3, fatG: 0.2, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil, fetchedAt: date
        )
        let food = SmartFoodLogic.customFood(from: product, pricePer100g: nil)
        XCTAssertEqual(food.imageURL, packshot)
        XCTAssertEqual(food.toScannedProduct(fetchedAt: date).imageURL, packshot)
    }

    func test_customFoodSavedBeforePictures_decodesWithoutOne() throws {
        let legacy = """
        {"id": "\(UUID().uuidString)", "name": "Gröt",
         "per100g": {"calories": 68, "proteinG": 2.4, "carbsG": 12, "fatG": 1.4},
         "updatedAt": 0}
        """
        let food = try JSONDecoder().decode(CustomFood.self, from: Data(legacy.utf8))
        XCTAssertNil(food.imageURL)
    }

    private func meal(source: MealSource, sourceID: String?) -> MealEntry {
        MealEntry(date: date, category: .breakfast, name: "Kvarg", calories: 120,
                  proteinG: 22, carbsG: 6, fatG: 0, sourceID: sourceID, source: source)
    }
}
