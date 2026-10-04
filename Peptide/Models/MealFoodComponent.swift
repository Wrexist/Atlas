import Foundation

/// Immutable-at-log snapshot: later catalog edits cannot rewrite food history.
struct MealFoodComponent: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var grams: Double
    var servingGrams: Double?
    var servingLabel: String?
    var per100g: ScannedProduct.Nutriments
    var sourceID: String?

    var fiberG: Double? { scaled(per100g.fiberG) }
    var sugarsG: Double? { scaled(per100g.sugarsG) }
    var macros: LoggableMeal? {
        let values = [per100g.calories, per100g.proteinG, per100g.carbsG, per100g.fatG]
            .map { $0 * grams / 100 }
        guard grams.isFinite, grams > 0, values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }) else { return nil }
        return LoggableMeal(calories: Int(values[0].rounded()), proteinG: Int(values[1].rounded()),
                           carbsG: Int(values[2].rounded()), fatG: Int(values[3].rounded()))
    }

    static func totals(_ components: [Self]) -> LoggableMeal? {
        let values = components.compactMap(\.macros)
        guard !values.isEmpty, values.count == components.count else { return nil }
        return LoggableMeal(calories: values.reduce(0) { $0 + $1.calories },
                           proteinG: values.reduce(0) { $0 + $1.proteinG },
                           carbsG: values.reduce(0) { $0 + $1.carbsG },
                           fatG: values.reduce(0) { $0 + $1.fatG })
    }
    private func scaled(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, grams.isFinite, grams > 0 else { return nil }
        let result = value * grams / 100
        return result.isFinite ? result : nil
    }

    /// A missing ingredient's nutrient is unknown, never an invented zero.
    static func completeTotal(_ values: [Double?]) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        let total = values.compactMap { $0 }.reduce(0, +)
        return total.isFinite ? total : nil
    }
}
