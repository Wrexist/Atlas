import Foundation

/// Finds the Open Food Facts packshot for a branded My Foods entry saved
/// without one: typed by hand, or read off a package by Atlas AI. Generic
/// foods keep their artwork, since a crowd photo of "rice" is any rice.
enum FoodPictureFinder {

    /// Searches one library visit may spend; the rest wait for the next.
    static let maxLookups = 3

    /// Foods whose search finished this launch, matched or not, so a food
    /// with no packshot never holds the queue. A search that was
    /// cancelled or throttled leaves its food eligible for the next visit.
    @MainActor static var tried: Set<UUID> = []

    struct Lookup: Equatable {
        var pictures: [UUID: URL] = [:]
        var searched: Set<UUID> = []
    }

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
    ) async -> Lookup {
        var lookup = Lookup()
        for food in foods {
            let query = [food.brand, food.name].compactMap { $0 }.joined(separator: " ")
            guard !Task.isCancelled, let results = try? await search(query) else { continue }
            lookup.searched.insert(food.id)
            lookup.pictures[food.id] = packshot(for: food, in: results)
        }
        return lookup
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
