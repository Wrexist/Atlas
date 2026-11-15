#if DEBUG
import Foundation

/// Screenshot runs only. A simulator has no camera, so this hands the
/// barcode review the product a real scan of a Loka Päron bottle returns:
/// a Swedish flavoured sparkling water, 50 cl, zero calories.
enum BarcodeDrinkFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--barcode-drink-fixture")
            && UserDefaults.standard.bool(forKey: "com.peptidesai.app.screenshotMode.enabled")
    }

    static func product(now: Date = Date()) -> ScannedProduct {
        ScannedProduct(
            barcode: "7310070765028",
            name: "Loka Päron",
            brand: "Loka",
            imageURL: nil,
            servingSizeText: nil,
            servingGrams: nil,
            packageGrams: 500,
            per100g: .init(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarsG: 0),
            nutriScore: "a",
            novaGroup: nil,
            fetchedAt: now,
            isDrink: true
        )
    }
}
#endif
