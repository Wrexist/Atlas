import Foundation

enum FoodLibraryLogic {
    /// Keep source nutrition intact; improve ordering within returned results.
    static func ranked(_ products: [ScannedProduct], query: String) -> [ScannedProduct] {
        let needle = normalized(query)
        let words = Set(needle.split(separator: " ").map(String.init))
        var seen = Set<String>()
        let unique = products.filter { seen.insert($0.barcode).inserted }
        func score(_ product: ScannedProduct) -> Int {
            let name = normalized(product.name)
            if name == needle { return 1000 }
            let nameWords = Set(name.split(separator: " ").map(String.init))
            return (name.hasPrefix(needle) ? 200 : 0)
                + words.intersection(nameWords).count * 50
                + (normalized(product.brand ?? "").contains(needle) ? 10 : 0)
        }
        guard !needle.isEmpty else { return unique }
        return unique.enumerated().sorted {
            let left = score($0.element), right = score($1.element)
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }

    static func previousGrams(for product: ScannedProduct, history: [MealEntry]) -> Double? {
        for entry in history.sorted(by: { $0.date > $1.date }) {
            guard entry.sourceID == product.barcode, let components = entry.components,
                  components.count == 1, let food = components.first,
                  food.grams.isFinite, (5...2000).contains(food.grams),
                  product.loggable(for: .grams(food.grams)) != nil else { continue }
            return food.grams
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
