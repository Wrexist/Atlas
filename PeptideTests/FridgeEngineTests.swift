import XCTest
@testable import Peptide

final class FridgeEngineTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(day: Int = 29, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func ingredient(_ key: String, name: String? = nil, nameSV: String? = nil) -> LibraryRecipe.Ingredient {
        LibraryRecipe.Ingredient(name: name ?? key.capitalized, nameSV: nameSV ?? key, grams: 100, pantryKey: key)
    }

    private func recipe(_ id: String, keys: [String]) -> LibraryRecipe {
        LibraryRecipe(
            id: id, name: id.capitalized, nameSV: id, category: .dinner, mealPrep: true, minutes: 30, servings: 4,
            fridgeDays: 4, tags: [], ingredients: keys.map { ingredient($0) }, steps: [], stepsSV: [],
            calories: 500, proteinG: 40, carbsG: 50, fatG: 10, fiberG: 6,
            micros: LibraryRecipe.Micros(sodiumMg: 0, potassiumMg: 0, ironMg: 0, calciumMg: 0, vitaminDUg: 0, vitaminB12Ug: 0),
            image: "recipe-\(id)"
        )
    }

    private func item(_ product: FridgeProduct, expiresOn: Date?) -> FridgeItem {
        FridgeItem(productID: product.id, place: .fridge, expiresOn: expiresOn, addedAt: date())
    }

    // MARK: - Freshness

    func test_freshness_countsWholeDaysFromToday() {
        let now = date(hour: 22)
        XCTAssertEqual(FridgeEngine.freshness(date(day: 27, hour: 0), now: now, calendar: calendar), .expired(daysAgo: 2))
        XCTAssertEqual(FridgeEngine.freshness(date(day: 29, hour: 0), now: now, calendar: calendar), .today)
        XCTAssertEqual(FridgeEngine.freshness(date(day: 30, hour: 0), now: now, calendar: calendar), .soon(daysLeft: 1))
        XCTAssertEqual(FridgeEngine.freshness(date(day: 31, hour: 0), now: now, calendar: calendar), .soon(daysLeft: 2))
        XCTAssertEqual(FridgeEngine.freshness(date(day: 1, month: 11, hour: 0), now: now, calendar: calendar), .fresh(daysLeft: 3))
        XCTAssertEqual(FridgeEngine.freshness(nil, now: now, calendar: calendar), .unknown)
    }

    func test_needsUse_coversExpiredTodayAndSoonOnly() {
        XCTAssertTrue(FridgeEngine.Freshness.expired(daysAgo: 1).needsUse)
        XCTAssertTrue(FridgeEngine.Freshness.today.needsUse)
        XCTAssertTrue(FridgeEngine.Freshness.soon(daysLeft: 2).needsUse)
        XCTAssertFalse(FridgeEngine.Freshness.fresh(daysLeft: 5).needsUse)
        XCTAssertFalse(FridgeEngine.Freshness.unknown.needsUse)
    }

    func test_defaultShelfDays_isCautiousAndNeverInventsCupboardDates() {
        XCTAssertEqual(FridgeEngine.defaultShelfDays(place: .fridge, pantryKey: "chicken breast"), 3)
        XCTAssertEqual(FridgeEngine.defaultShelfDays(place: .fridge, pantryKey: "milk"), 10)
        XCTAssertEqual(FridgeEngine.defaultShelfDays(place: .freezer, pantryKey: "chicken breast"), 90)
        XCTAssertNil(FridgeEngine.defaultShelfDays(place: .pantry, pantryKey: "pasta"))
        XCTAssertNil(FridgeEngine.defaultShelfDays(place: .fridge, pantryKey: nil))
    }

    // MARK: - Recipe keys

    func test_pantryKey_matchesSwedishCompoundsByTheirHead() {
        let ingredients = [
            ingredient("milk", nameSV: "Mellanmjölk"),
            ingredient("garlic", nameSV: "Vitlök"),
            ingredient("onion", nameSV: "Lök"),
            ingredient("cream", nameSV: "Vispgrädde 40 %"),
        ]
        XCTAssertEqual(FridgeEngine.pantryKey(for: "Mjölk", ingredients: ingredients), "milk")
        XCTAssertEqual(FridgeEngine.pantryKey(for: "Vitlök", ingredients: ingredients), "garlic")
        XCTAssertEqual(FridgeEngine.pantryKey(for: "Rödlök", ingredients: ingredients), "onion")
        XCTAssertEqual(FridgeEngine.pantryKey(for: "Garlic", ingredients: ingredients), "garlic")
        XCTAssertNil(FridgeEngine.pantryKey(for: "Diskmedel", ingredients: ingredients))
    }

    func test_pantryKeys_leaveOutExpiredItems() {
        let milk = FridgeProduct(name: "Mjölk", pantryKey: "milk")
        let cream = FridgeProduct(name: "Grädde", pantryKey: "cream")
        let products = [milk.id: milk, cream.id: cream]
        let items = [item(milk, expiresOn: date(day: 31)), item(cream, expiresOn: date(day: 27))]

        let keys = FridgeEngine.pantryKeys(items: items, products: products, now: date(), calendar: calendar)

        XCTAssertEqual(keys, ["milk"])
    }

    // MARK: - Cooking from the fridge

    func test_suggestions_putRecipesSavingExpiringFoodFirst() {
        let recipes = [
            recipe("pasta", keys: ["pasta", "cream", "salmon"]),
            recipe("curry", keys: ["chicken breast", "rice", "coconut milk"]),
        ]
        let suggestions = FridgeEngine.suggestions(
            recipes: recipes,
            have: ["pasta", "cream", "salmon", "chicken breast", "rice"],
            fridgeKeys: ["cream", "salmon", "chicken breast"],
            expiringKeys: ["chicken breast"]
        )

        XCTAssertEqual(suggestions.map(\.recipe.id), ["curry", "pasta"])
        XCTAssertEqual(suggestions.first?.missing.map(\.pantryKey), ["coconut milk"])
        XCTAssertEqual(suggestions.last?.missing, [])
    }

    func test_suggestions_needTheFridgeToContribute() {
        let recipes = [recipe("toast", keys: ["whole grain bread", "butter"])]
        let suggestions = FridgeEngine.suggestions(
            recipes: recipes, have: ["whole grain bread", "butter"], fridgeKeys: ["milk"], expiringKeys: []
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func test_suggestions_skipMostlyMissingRecipesUnlessTheySaveSomething() {
        let recipes = [recipe("stew", keys: ["beef", "potato", "carrot", "onion"])]
        let notSaving = FridgeEngine.suggestions(recipes: recipes, have: ["beef"], fridgeKeys: ["beef"], expiringKeys: [])
        let saving = FridgeEngine.suggestions(recipes: recipes, have: ["beef"], fridgeKeys: ["beef"], expiringKeys: ["beef"])

        XCTAssertTrue(notSaving.isEmpty)
        XCTAssertEqual(saving.first?.missing.count, 3)
    }

    // MARK: - Listing

    func test_sorted_putsSoonestFirstAndUndatedLast() {
        let a = FridgeProduct(name: "Ägg")
        let b = FridgeProduct(name: "Banan")
        let c = FridgeProduct(name: "Citron")
        let products = [a.id: a, b.id: b, c.id: c]
        let items = [item(c, expiresOn: nil), item(b, expiresOn: date(day: 31)), item(a, expiresOn: date(day: 30))]

        let sorted = FridgeEngine.sorted(items, products: products)

        XCTAssertEqual(sorted.map(\.productID), [a.id, b.id, c.id])
    }

    func test_search_matchesEveryWordAndListsRecentFirst() {
        var old = FridgeProduct(name: "Mellanmjölk", brand: "Arla")
        old.lastAddedAt = date(day: 1)
        var recent = FridgeProduct(name: "Mjölk laktosfri", brand: "Arla")
        recent.lastAddedAt = date(day: 20)
        let other = FridgeProduct(name: "Smör", brand: "Bregott")

        XCTAssertEqual(FridgeEngine.search([old, recent, other], query: "arla mjölk").map(\.id), [recent.id, old.id])
        XCTAssertEqual(FridgeEngine.search([old, recent, other], query: "").count, 3)
    }

    // MARK: - Reminders

    func test_nextReminder_firesTheEveningBeforeAndGroupsTheDay() {
        let milk = FridgeProduct(name: "Mjölk")
        let cream = FridgeProduct(name: "Grädde")
        let late = FridgeProduct(name: "Ost")
        let items = [item(milk, expiresOn: date(day: 31, hour: 0)), item(cream, expiresOn: date(day: 31, hour: 0)),
                     item(late, expiresOn: date(day: 5, month: 11, hour: 0))]

        let reminder = FridgeEngine.nextReminder(for: items, now: date(), calendar: calendar)

        XCTAssertEqual(reminder?.fireDate, date(day: 30, hour: FridgeEngine.eveningHour))
        XCTAssertEqual(reminder?.itemIDs.count, 2)
    }

    func test_nextReminder_fallsBackToThatMorningWhenTheEveningHasPassed() {
        let milk = FridgeProduct(name: "Mjölk")
        let items = [item(milk, expiresOn: date(day: 30, hour: 0))]

        let reminder = FridgeEngine.nextReminder(for: items, now: date(day: 29, hour: 20), calendar: calendar)

        XCTAssertEqual(reminder?.fireDate, date(day: 30, hour: FridgeEngine.morningHour))
        XCTAssertEqual(reminder?.useBy, date(day: 30, hour: 0))
    }

    func test_nextReminder_skipsDaysAlreadyGone() {
        let milk = FridgeProduct(name: "Mjölk")
        let items = [item(milk, expiresOn: date(day: 28, hour: 0))]
        XCTAssertNil(FridgeEngine.nextReminder(for: items, now: date(), calendar: calendar))
    }
}
