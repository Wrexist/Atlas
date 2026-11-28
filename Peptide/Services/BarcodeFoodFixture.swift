#if DEBUG
import Foundation

/// Screenshot runs only. A simulator has no camera, so this hands the
/// barcode review a Greek yoghurt with a full Swedish nutrition panel:
/// every macro split, cholesterol, sodium, potassium and calcium.
enum BarcodeFoodFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--barcode-food-fixture")
            && UserDefaults.standard.bool(forKey: "com.peptidesai.app.screenshotMode.enabled")
    }

    static func product(now: Date = Date()) -> ScannedProduct {
        ScannedProduct(
            barcode: "7310865004703",
            name: "Grekisk yoghurt 10 %",
            brand: "Arla",
            imageURL: nil,
            servingSizeText: "150 g",
            servingGrams: 150,
            packageGrams: 1_000,
            per100g: .init(
                calories: 122, proteinG: 4.3, carbsG: 4.2, fatG: 10, fiberG: 0, sugarsG: 4.2,
                micros: Micronutrients(
                    sodiumMg: 52, potassiumMg: 150, calciumMg: 140,
                    saturatedFatG: 6.6, cholesterolMg: 30
                )
            ),
            nutriScore: "c",
            novaGroup: 1,
            fetchedAt: now
        )
    }
}
#endif
