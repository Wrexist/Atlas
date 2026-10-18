import Foundation

/// Swaps the model's estimate for real data where a scanned food has
/// some, the way MacroFactor does: the model identifies, a database
/// supplies the numbers. The user's own saved foods come first, then
/// Open Food Facts for branded products. Generic foods ("rice") keep the
/// estimate; crowd records for those are noisier than the model.
enum FoodGrounding {

    typealias Search = @Sendable (String) async throws -> [ScannedProduct]

    /// A database value this far from the estimate is more likely a
    /// different product than a better number for the same one.
    static let maxCalorieRatio = 2.0
    /// Open Food Facts allows the app 8 searches a minute.
    static let maxLookups = 3
    /// Grounding is a bonus; the review screen never waits long for it.
    static let lookupTimeout: Duration = .seconds(3)

    static func ground(
        _ items: [MealScannerService.ScannedFoodItem],
        myFoods: [CustomFood],
        search: @escaping Search = { try await OpenFoodFactsService.shared.search(query: $0) }
    ) async -> [MealScannerService.ScannedFoodItem] {
        let saved = items.map { match($0, in: myFoods) }
        let lookups = items.indices.filter { items[$0].brand != nil && saved[$0] == nil }.prefix(maxLookups)
        let found = await withTaskGroup(of: (Int, ScannedProduct?).self) { group in
            for index in lookups {
                let item = items[index]
                group.addTask {
                    let query = [item.brand, item.name].compactMap { $0 }.joined(separator: " ")
                    let results = await withTimeout(lookupTimeout) { try await search(query) }
                    return (index, results.flatMap { bestProduct(for: item, in: $0) })
                }
            }
            var found: [Int: ScannedProduct] = [:]
            for await (index, product) in group { found[index] = product }
            return found
        }
        return items.indices.map { index in
            let item = items[index]
            if let food = saved[index] {
                return applying(food.per100g, from: .myFoods, to: item,
                                fallbackPrice: food.pricePer100g?.scaled(by: item.grams / 100))
            }
            if let product = found[index] {
                return applying(product.per100g, from: .openFoodFacts, to: item, fallbackPrice: nil)
            }
            return item
        }
    }

    /// A saved food with the same name, and the same brand when both
    /// have one.
    static func match(_ item: MealScannerService.ScannedFoodItem, in myFoods: [CustomFood]) -> CustomFood? {
        let name = FoodLibraryLogic.normalized(item.name)
        guard !name.isEmpty else { return nil }
        return myFoods.first { food in
            FoodLibraryLogic.normalized(food.name) == name
                && (item.brand == nil || food.brand == nil
                    || FoodLibraryLogic.normalized(food.brand ?? "") == FoodLibraryLogic.normalized(item.brand ?? ""))
                && isPlausible(food.per100g, against: item)
        }
    }

    /// The best search hit that is clearly the same product: same brand,
    /// every word of the scanned name, and believable calories.
    static func bestProduct(for item: MealScannerService.ScannedFoodItem, in results: [ScannedProduct]) -> ScannedProduct? {
        let brand = FoodLibraryLogic.normalized(item.brand ?? "")
        let words = FoodLibraryLogic.normalized(item.name).split(separator: " ")
        guard !brand.isEmpty, !words.isEmpty else { return nil }
        return FoodLibraryLogic.ranked(results, query: item.name).first { product in
            let nameWords = Set(FoodLibraryLogic.normalized(product.name).split(separator: " "))
            return FoodLibraryLogic.normalized(product.brand ?? "").contains(brand)
                && words.allSatisfy(nameWords.contains)
                && isPlausible(product.per100g, against: item)
        }
    }

    private static func isPlausible(_ values: ScannedProduct.Nutriments, against item: MealScannerService.ScannedFoodItem) -> Bool {
        let estimate = SmartFoodLogic.per100g(of: item).calories
        guard values.calories > 0, values.calories <= 900, estimate > 0 else { return false }
        let ratio = values.calories / estimate
        return (1 / maxCalorieRatio...maxCalorieRatio).contains(ratio)
    }

    /// The same item with database values. The follow-up question goes:
    /// its answers were the model's estimates for a food now known.
    private static func applying(
        _ per100g: ScannedProduct.Nutriments,
        from source: VerifiedFoodSource,
        to item: MealScannerService.ScannedFoodItem,
        fallbackPrice: FoodPriceEstimate?
    ) -> MealScannerService.ScannedFoodItem {
        let scale = item.grams / 100
        return MealScannerService.ScannedFoodItem(
            name: item.name,
            quantityLabel: item.quantityLabel,
            grams: item.grams,
            calories: Int((per100g.calories * scale).rounded()),
            proteinG: Int((per100g.proteinG * scale).rounded()),
            carbsG: Int((per100g.carbsG * scale).rounded()),
            fatG: Int((per100g.fatG * scale).rounded()),
            confidence: item.confidence,
            brand: item.brand,
            per100g: per100g,
            portionOptions: item.portionOptions,
            price: item.price ?? fallbackPrice,
            verifiedBy: source
        )
    }

    private static func withTimeout<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
