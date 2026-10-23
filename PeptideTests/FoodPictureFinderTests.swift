import XCTest
@testable import Peptide

final class FoodPictureFinderTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_760_000_000)
    private let packshot = URL(string: "https://images.openfoodfacts.org/images/products/731/front_sv.400.jpg")!

    func test_sameBrandAndName_findsThePackshot() {
        let food = food("Kvarg Vanilj", brand: "Arla", kcal: 70)
        let hits = [product("Kvarg Vanilj", brand: "Arla", kcal: 72, image: packshot)]
        XCTAssertEqual(FoodPictureFinder.packshot(for: food, in: hits), packshot)
    }

    func test_brandRepeatedInTheName_stillMatches() {
        let food = food("Arla Kvarg", brand: "Arla", kcal: 60)
        let hits = [product("Kvarg naturell", brand: "Arla Foods", kcal: 61, image: packshot)]
        XCTAssertEqual(FoodPictureFinder.packshot(for: food, in: hits), packshot)
    }

    func test_otherBrand_isNotTheSameProduct() {
        let food = food("Kvarg Vanilj", brand: "Arla", kcal: 70)
        let hits = [product("Kvarg Vanilj", brand: "Lindahls", kcal: 70, image: packshot)]
        XCTAssertNil(FoodPictureFinder.packshot(for: food, in: hits))
    }

    func test_farOffCalories_areADifferentProduct() {
        let food = food("Kvarg", brand: "Arla", kcal: 60)
        let hits = [product("Kvarg", brand: "Arla", kcal: 400, image: packshot)]
        XCTAssertNil(FoodPictureFinder.packshot(for: food, in: hits))
    }

    func test_matchWithoutImage_isSkippedForOneWithImage() {
        let food = food("Kvarg", brand: "Arla", kcal: 60)
        let hits = [
            product("Kvarg", brand: "Arla", kcal: 60, image: nil),
            product("Kvarg", brand: "Arla", kcal: 61, image: packshot, barcode: "2"),
        ]
        XCTAssertEqual(FoodPictureFinder.packshot(for: food, in: hits), packshot)
    }

    func test_candidates_skipGenericPicturedAndTriedFoods() {
        let generic = food("Banan", brand: nil, kcal: 89)
        var pictured = food("Kvarg", brand: "Arla", kcal: 60)
        pictured.imageURL = packshot
        let tried = food("Yoghurt", brand: "Valio", kcal: 50)
        let waiting = food("Havredryck", brand: "Oatly", kcal: 46)
        let picked = FoodPictureFinder.candidates(in: [generic, pictured, tried, waiting], skipping: [tried.id])
        XCTAssertEqual(picked.map(\.id), [waiting.id])
    }

    func test_candidates_areCappedPerVisit() {
        let foods = (0..<10).map { food("Bar \($0)", brand: "Barebells", kcal: 350) }
        XCTAssertEqual(FoodPictureFinder.candidates(in: foods, skipping: []).count, FoodPictureFinder.maxLookups)
    }

    func test_find_searchesBrandAndNameAndSkipsMisses() async {
        let kvarg = food("Kvarg", brand: "Arla", kcal: 60)
        let bar = food("Salty Peanut", brand: "Barebells", kcal: 350)
        let hit = product("Kvarg", brand: "Arla", kcal: 60, image: packshot)
        let found = await FoodPictureFinder.find(for: [kvarg, bar]) { query in
            query == "Arla Kvarg" ? [hit] : []
        }
        XCTAssertEqual(found, [kvarg.id: packshot])
    }

    private func food(_ name: String, brand: String?, kcal: Double) -> CustomFood {
        CustomFood(name: name, brand: brand,
                   per100g: .init(calories: kcal, proteinG: 10, carbsG: 5, fatG: 1, fiberG: nil, sugarsG: nil),
                   updatedAt: date)
    }

    private func product(_ name: String, brand: String, kcal: Double, image: URL?, barcode: String = "1") -> ScannedProduct {
        ScannedProduct(
            barcode: barcode, name: name, brand: brand, imageURL: image,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .init(calories: kcal, proteinG: 10, carbsG: 5, fatG: 1, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil, fetchedAt: date
        )
    }
}
