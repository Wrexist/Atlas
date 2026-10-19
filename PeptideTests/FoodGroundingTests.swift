import XCTest
@testable import Peptide

/// Database values replace the model's estimate only for a food that is
/// clearly the same: the user's own saved food, or a same-brand Open Food
/// Facts hit with believable calories.
final class FoodGroundingTests: XCTestCase {

    private func item(_ name: String, brand: String? = nil, kcal: Double = 60, grams: Double = 250) -> MealScannerService.ScannedFoodItem {
        MealScannerService.ScannedFoodItem(
            name: name, quantityLabel: "1 glass", grams: grams,
            calories: Int(kcal * grams / 100), proteinG: 1, carbsG: 6, fatG: 3, confidence: 0.9,
            brand: brand,
            per100g: .init(calories: kcal, proteinG: 1, carbsG: 6, fatG: 3, fiberG: nil, sugarsG: nil),
            question: ScanQuestion(question: "Barista?", answers: [])
        )
    }

    private func product(_ name: String, brand: String?, kcal: Double) -> ScannedProduct {
        ScannedProduct(barcode: UUID().uuidString, name: name, brand: brand, imageURL: nil,
                       servingSizeText: nil, servingGrams: nil, packageGrams: nil,
                       per100g: .init(calories: kcal, proteinG: 1.1, carbsG: 6.6, fatG: 3, fiberG: 0.8, sugarsG: 3.4),
                       nutriScore: nil, novaGroup: nil, fetchedAt: Date())
    }

    func test_savedFood_beatsEstimate_andLendsItsPrice() async {
        let mine = CustomFood(name: "havremjölk", per100g: .init(calories: 46, proteinG: 1, carbsG: 7, fatG: 1.5, fiberG: nil, sugarsG: nil),
                              pricePer100g: FoodPriceEstimate(low: 2, high: 3, currency: "SEK", basis: .store))
        let grounded = await FoodGrounding.ground([item("Havremjölk")], myFoods: [mine]) { _ in
            XCTFail("a saved match needs no search")
            return []
        }
        XCTAssertEqual(grounded.first?.verifiedBy, .myFoods)
        XCTAssertEqual(grounded.first?.calories, 115, "46 kcal/100 g × 250 g")
        XCTAssertEqual(grounded.first?.price?.high ?? 0, 7.5, accuracy: 0.001)
        XCTAssertNil(grounded.first?.question, "the estimate's answers no longer apply")
    }

    func test_brandedItem_takesSameProductFromOpenFoodFacts() async {
        let hits = [product("Oat Drink Chocolate", brand: "Oatly", kcal: 70),
                    product("Barista Edition Oat Drink", brand: "Oatly", kcal: 59)]
        let grounded = await FoodGrounding.ground([item("Barista oat drink", brand: "Oatly")], myFoods: []) { query in
            XCTAssertEqual(query, "Oatly Barista oat drink")
            return hits
        }
        XCTAssertEqual(grounded.first?.verifiedBy, .openFoodFacts)
        XCTAssertEqual(grounded.first?.per100g?.fiberG, 0.8)
    }

    func test_differentBrandOrImplausibleCalories_keepsEstimate() {
        let scanned = item("Barista oat drink", brand: "Oatly")
        XCTAssertNil(FoodGrounding.bestProduct(for: scanned, in: [product("Barista Oat Drink", brand: "Alpro", kcal: 59)]))
        XCTAssertNil(FoodGrounding.bestProduct(for: scanned, in: [product("Barista Oat Drink", brand: "Oatly", kcal: 400)]))
    }

    func test_genericFood_isNeverLookedUp_andFailedSearchKeepsEstimate() async {
        struct Offline: Error {}
        let grounded = await FoodGrounding.ground([item("Rice"), item("Oat drink", brand: "Oatly")], myFoods: []) { query in
            XCTAssertFalse(query.contains("Rice"))
            throw Offline()
        }
        XCTAssertEqual(grounded.map(\.verifiedBy), [nil, nil])
        XCTAssertEqual(grounded.map(\.calories), [150, 150])
    }
}
