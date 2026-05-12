import XCTest
@testable import Peptide

final class ScannedProductTests: XCTestCase {

    // MARK: - Fixtures

    /// Coca-Cola-shaped product: a 330 g serving, a 330 g package, and
    /// per-100g energy at 42 kcal — the textbook OFF example.
    private func cokeLike() -> ScannedProduct {
        ScannedProduct(
            barcode: "5449000000996",
            name: "Coca-Cola",
            brand: "Coca-Cola",
            imageURL: nil,
            servingSizeText: "330 ml",
            servingGrams: 330,
            packageGrams: 330,
            per100g: .init(calories: 42, proteinG: 0, carbsG: 10.6, fatG: 0, fiberG: 0, sugarsG: 10.6),
            nutriScore: "e",
            novaGroup: 4,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// A bulk-ingredient-shaped product: no serving info, no package
    /// weight, only per-100g macros. Exercises the .grams() fallback.
    private func bulkRiceLike() -> ScannedProduct {
        ScannedProduct(
            barcode: "0000000000001",
            name: "Long-grain rice",
            brand: nil,
            imageURL: nil,
            servingSizeText: nil,
            servingGrams: nil,
            packageGrams: nil,
            per100g: .init(calories: 365, proteinG: 7.1, carbsG: 80, fatG: 0.7, fiberG: 1.3, sugarsG: 0.1),
            nutriScore: nil,
            novaGroup: nil,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Portion math: .grams

    func test_loggable_grams100_returnsPer100gRounded() {
        let p = bulkRiceLike()
        let meal = p.loggable(for: .grams(100))
        XCTAssertEqual(meal?.calories, 365)
        XCTAssertEqual(meal?.proteinG, 7)        // 7.1 → 7
        XCTAssertEqual(meal?.carbsG, 80)
        XCTAssertEqual(meal?.fatG, 1)            // 0.7 → 1
    }

    func test_loggable_grams200_doublesAllMacros() {
        let p = bulkRiceLike()
        let meal = p.loggable(for: .grams(200))
        XCTAssertEqual(meal?.calories, 730)
        XCTAssertEqual(meal?.proteinG, 14)       // 14.2 → 14
        XCTAssertEqual(meal?.carbsG, 160)
        XCTAssertEqual(meal?.fatG, 1)            // 1.4 → 1
    }

    func test_loggable_grams50_halvesAllMacros() {
        let p = bulkRiceLike()
        let meal = p.loggable(for: .grams(50))
        XCTAssertEqual(meal?.calories, 183)      // 365 * 0.5 = 182.5 → 183 (Swift's .rounded() uses .toNearestOrAwayFromZero)
        XCTAssertEqual(meal?.carbsG, 40)
    }

    func test_loggable_grams0_returnsNil() {
        XCTAssertNil(bulkRiceLike().loggable(for: .grams(0)))
    }

    func test_loggable_gramsNegative_returnsNil() {
        XCTAssertNil(bulkRiceLike().loggable(for: .grams(-50)))
    }

    // MARK: - Portion math: .servings

    func test_loggable_oneServing_usesServingGrams() {
        let p = cokeLike()                       // 330 g serving, 42 kcal/100g
        let meal = p.loggable(for: .servings(1))
        XCTAssertEqual(meal?.calories, 139)      // 42 * 3.3 = 138.6 → 139
        XCTAssertEqual(meal?.carbsG, 35)         // 10.6 * 3.3 = 34.98 → 35
    }

    func test_loggable_twoServings_scalesFromPer100g() {
        // Two servings of Coke = 660 g.
        // 42 * 6.6 = 277.2 → 277. 10.6 * 6.6 = 69.96 → 70.
        // We assert against per-100g math directly rather than against
        // `one * 2` — each portion is rounded independently, so
        // round(x) * 2 != round(2x) in general.
        let p = cokeLike()
        let two = p.loggable(for: .servings(2))!
        XCTAssertEqual(two.calories, 277)
        XCTAssertEqual(two.carbsG, 70)
    }

    func test_loggable_halfServing_halves() {
        let p = cokeLike()
        let meal = p.loggable(for: .servings(0.5))
        XCTAssertEqual(meal?.calories, 69)       // 42 * 1.65 = 69.3 → 69
    }

    func test_loggable_servings_returnsNil_whenServingGramsMissing() {
        XCTAssertNil(bulkRiceLike().loggable(for: .servings(1)))
    }

    // MARK: - Portion math: .wholePackage

    func test_loggable_wholePackage_usesPackageGrams() {
        let p = cokeLike()                       // package == 330 g
        let meal = p.loggable(for: .wholePackage)
        XCTAssertEqual(meal?.calories, 139)      // same as one serving
    }

    func test_loggable_wholePackage_returnsNil_whenPackageGramsMissing() {
        XCTAssertNil(bulkRiceLike().loggable(for: .wholePackage))
    }

    // MARK: - Default portion selection

    func test_defaultPortion_prefersServings_whenAvailable() {
        XCTAssertEqual(cokeLike().defaultPortion, .servings(1))
    }

    func test_defaultPortion_fallsBackTo100g_whenNoServingAndNoPackage() {
        XCTAssertEqual(bulkRiceLike().defaultPortion, .grams(100))
    }

    func test_defaultPortion_usesWholePackage_whenSmallPackageAndNoServing() {
        let p = ScannedProduct(
            barcode: "8888888888888",
            name: "Small snack",
            brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil,
            packageGrams: 40,                    // ≤ 500 g threshold
            per100g: .init(calories: 500, proteinG: 5, carbsG: 50, fatG: 25, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(p.defaultPortion, .wholePackage)
    }

    func test_defaultPortion_falls_through_to_100g_for_largePackage() {
        let p = ScannedProduct(
            barcode: "8888888888889",
            name: "Family bag",
            brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil,
            packageGrams: 1000,                  // > 500 g threshold
            per100g: .init(calories: 500, proteinG: 5, carbsG: 50, fatG: 25, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(p.defaultPortion, .grams(100))
    }

    // MARK: - Robustness

    func test_loggable_clampsNegativePer100gToZero() {
        let weird = ScannedProduct(
            barcode: "9999999999999",
            name: "Corrupted entry",
            brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil,
            packageGrams: nil,
            per100g: .init(calories: -100, proteinG: -1, carbsG: -1, fatG: -1, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        let meal = weird.loggable(for: .grams(100))
        XCTAssertEqual(meal?.calories, 0)
        XCTAssertEqual(meal?.proteinG, 0)
        XCTAssertEqual(meal?.carbsG, 0)
        XCTAssertEqual(meal?.fatG, 0)
    }

    // MARK: - grams(for:) helper

    func test_gramsFor_servings_multipliesServingGrams() {
        XCTAssertEqual(cokeLike().grams(for: .servings(2)), 660)
    }

    func test_gramsFor_wholePackage_returnsPackageGrams() {
        XCTAssertEqual(cokeLike().grams(for: .wholePackage), 330)
    }

    func test_gramsFor_grams_isIdentity() {
        XCTAssertEqual(cokeLike().grams(for: .grams(123.4)), 123.4)
    }
}
