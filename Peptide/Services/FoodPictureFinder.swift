import Foundation

/// Finds the Open Food Facts packshot for a branded My Foods entry saved
/// without one: typed by hand, or read off a package by Atlas AI. Generic
/// foods keep their artwork, since a crowd photo of "rice" is any rice.
enum FoodPictureFinder {

    /// Searches one library visit may spend; the rest wait for the next.
    static let maxLookups = 3

    /// Foods already looked up this launch, matched or not, so a food
    /// with no packshot never holds the queue.
    @MainActor static var tried: Set<UUID> = []

    static func candidates(in foods: [CustomFood], skipping tried: Set<UUID>) -> [CustomFood] {
        Array(foods.lazy.filter { food in
            food.imageURL == nil
                && !FoodLibraryLogic.normalized(food.brand ?? "").isEmpty
                && !tried.contains(food.id)
        }.prefix(maxLookups))
    }

    static func find(
        for foods: [CustomFood],
        search: FoodGrounding.Search = {
            try await OpenFoodFactsService.shared.search(query: $0, leavingFree: FoodGrounding.slotsKeptForUser)
        }
    ) async -> [UUID: URL] {
        var found: [UUID: URL] = [:]
        for food in foods {
            let query = [food.brand, food.name].compactMap { $0 }.joined(separator: " ")
            guard let results = try? await search(query),
                  let url = packshot(for: food, in: results)
            else { continue }
            found[food.id] = url
        }
        return found
    }

    /// The image of the hit that is clearly the same product: the same
    /// brand, every other word of the food's name, believable calories.
    static func packshot(for food: CustomFood, in results: [ScannedProduct]) -> URL? {
        let brand = FoodLibraryLogic.normalized(food.brand ?? "")
        let brandWords = Set(brand.split(separator: " "))
        let words = FoodLibraryLogic.normalized(food.name).split(separator: " ").filter { !brandWords.contains($0) }
        guard !brand.isEmpty, !words.isEmpty else { return nil }
        return FoodLibraryLogic.ranked(results, query: food.name).first { product in
            let nameWords = Set(FoodLibraryLogic.normalized(product.name).split(separator: " "))
            return product.imageURL != nil
                && FoodLibraryLogic.normalized(product.brand ?? "").contains(brand)
                && words.allSatisfy(nameWords.contains)
                && caloriesAgree(food.per100g.calories, product.per100g.calories)
        }?.imageURL
    }

    private static func caloriesAgree(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs > 0, rhs > 0 else { return true }
        return max(lhs, rhs) / min(lhs, rhs) <= FoodGrounding.maxCalorieRatio
    }
}
