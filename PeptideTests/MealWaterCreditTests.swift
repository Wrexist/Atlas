import XCTest
@testable import Peptide

/// A hydrating drink's water travels with its meal entry, so every way
/// of logging, deleting or re-portioning it moves the day's water too.
final class MealWaterCreditTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 2026-03-10 12:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_773_144_000)

    private func drink(grams: Double = 500, water: Double? = 500) -> MealEntry {
        let component = MealFoodComponent(
            id: "7310070000000", name: "Sparkling water", grams: grams, servingGrams: nil, servingLabel: nil,
            per100g: ScannedProduct.Nutriments(calories: 0.4, proteinG: 0, carbsG: 0.1, fatG: 0, fiberG: nil, sugarsG: nil),
            sourceID: "7310070000000", isDrink: true
        )
        return MealEntry(date: noon, category: .snack, name: "Sparkling water", calories: 2,
                         proteinG: 0, carbsG: 1, fatG: 0, sourceID: "7310070000000",
                         source: .openFoodFacts, components: [component], waterMillilitres: water)
    }

    private func waterMillilitres(in profile: UserProfile) -> Int {
        LifestyleDataLogic.millilitres(
            fluidOunces: LifestyleDataLogic.consumption(in: profile, for: noon, calendar: calendar).waterFluidOunces
        )
    }

    func test_logDrink_addsItsWaterToTheDay() {
        var profile = UserProfile.fresh
        LifestyleDataLogic.logMealEntry(into: &profile, entry: drink(), calendar: calendar)
        XCTAssertEqual(waterMillilitres(in: profile), 500)
    }

    func test_logThenDeleteDrink_restoresDayWater() {
        var profile = UserProfile.fresh
        LifestyleDataLogic.logWater(
            into: &profile, fluidOunces: LifestyleDataLogic.fluidOunces(millilitres: 250), date: noon, calendar: calendar
        )
        let entry = drink()
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry, calendar: calendar)
        LifestyleDataLogic.unlogMealEntry(from: &profile, id: entry.id, calendar: calendar)
        XCTAssertEqual(waterMillilitres(in: profile), 250)
    }

    func test_editDrinkPortion_rescalesItsWater() {
        var profile = UserProfile.fresh
        let entry = drink()
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry, calendar: calendar)
        var doubled = entry
        doubled.components?[0].grams = 1000
        LifestyleDataLogic.applyMealEntryEdit(into: &profile, updated: doubled, calendar: calendar)
        XCTAssertEqual(waterMillilitres(in: profile), 1000)
        XCTAssertEqual(profile.mealHistory.first?.waterMillilitres, 1000)
    }

    func test_relogDrink_carriesItsWater() {
        var profile = UserProfile.fresh
        let entry = drink()
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry, calendar: calendar)
        LifestyleDataLogic.logMealEntry(into: &profile, entry: LifestyleDataLogic.relogged(entry, at: noon), calendar: calendar)
        XCTAssertEqual(waterMillilitres(in: profile), 1000)
    }

    func test_logFood_leavesWaterAlone() {
        var profile = UserProfile.fresh
        LifestyleDataLogic.logMealEntry(into: &profile, entry: drink(water: nil), calendar: calendar)
        XCTAssertEqual(waterMillilitres(in: profile), 0)
    }

    func test_legacyEntryWithoutWaterField_decodes() throws {
        // Encoded with the field, then stripped, so the decode really
        // meets a payload written before the field existed.
        let entry = drink(water: 500)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "waterMillilitres"))
        let decoded = try JSONDecoder().decode(MealEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.waterMillilitres)
    }

    func test_scannedDrinkComponent_carriesDrinkFlag() throws {
        var product = ScannedProduct(
            barcode: "7310070000000", name: "Sparkling water", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: 330, packageGrams: nil,
            per100g: ScannedProduct.Nutriments(calories: 0.4, proteinG: 0, carbsG: 0.1, fatG: 0, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil, fetchedAt: Date()
        )
        product.isDrink = true
        let meal = try XCTUnwrap(product.loggable(for: .servings(1)))
        XCTAssertEqual(meal.components?.first?.isDrink, true)
    }
}
