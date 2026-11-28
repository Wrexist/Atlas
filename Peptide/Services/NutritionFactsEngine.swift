import Foundation

/// The nutrition-label breakdown of one portion or one logged meal: the
/// three macros with what they are made of, then the minerals and
/// vitamins. Every amount is for the whole portion, and an amount the
/// label or scan didn't state stays nil, never an invented zero.
enum NutritionFactsEngine {

    enum Nutrient: String, CaseIterable, Identifiable, Sendable {
        case energy
        case protein
        case carbs, fiber, sugars
        case fat, saturatedFat, unsaturatedFat
        case cholesterol, sodium, potassium
        case calcium, iron, vitaminD, vitaminB12

        var id: Self { self }

        var unit: Unit {
            switch self {
            case .energy: .kilocalories
            case .carbs, .fiber, .sugars, .protein, .fat, .saturatedFat, .unsaturatedFat: .grams
            case .cholesterol, .sodium, .potassium, .calcium, .iron: .milligrams
            case .vitaminD, .vitaminB12: .micrograms
            }
        }
    }

    enum Unit: String, Sendable {
        case kilocalories = "kcal"
        case grams = "g"
        case milligrams = "mg"
        case micrograms = "µg"
    }

    /// One row group, in label order. A part (fibre under carbs) sits
    /// indented under its total.
    struct Group: Hashable, Sendable {
        let total: Nutrient?
        let parts: [Nutrient]
        /// The vitamins group lists only what is known: four dashes on
        /// most foods would be noise, not information.
        let hidesUnknown: Bool
    }

    /// Macros in the totals card's order (protein, carbs, fat), so the
    /// two cards on one screen read the same way.
    static let groups: [Group] = [
        Group(total: .energy, parts: [], hidesUnknown: false),
        Group(total: .protein, parts: [], hidesUnknown: false),
        Group(total: .carbs, parts: [.fiber, .sugars], hidesUnknown: false),
        Group(total: .fat, parts: [.saturatedFat, .unsaturatedFat], hidesUnknown: false),
        Group(total: nil, parts: [.cholesterol, .sodium, .potassium], hidesUnknown: false),
        Group(total: nil, parts: [.calcium, .iron, .vitaminD, .vitaminB12], hidesUnknown: true),
    ]

    /// The amount in 100 g. Unsaturated fat, when not stated, is what is
    /// left of the fat once the saturated part is taken out: labels
    /// rarely print it, and fat is saturated or unsaturated bar a trace
    /// of trans fat.
    static func per100g(_ nutrient: Nutrient, in n: ScannedProduct.Nutriments) -> Double? {
        let value: Double? = switch nutrient {
        case .energy: n.calories
        case .carbs: n.carbsG
        case .fiber: n.fiberG
        case .sugars: n.sugarsG
        case .protein: n.proteinG
        case .fat: n.fatG
        case .saturatedFat: saturatedFat(in: n)
        case .unsaturatedFat: unsaturatedFat(in: n)
        case .cholesterol: n.micros?.cholesterolMg
        case .sodium: n.micros?.sodiumMg
        case .potassium: n.micros?.potassiumMg
        case .calcium: n.micros?.calciumMg
        case .iron: n.micros?.ironMg
        case .vitaminD: n.micros?.vitaminDUg
        case .vitaminB12: n.micros?.vitaminB12Ug
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// The amount in `grams` of the food.
    static func amount(_ nutrient: Nutrient, per100g n: ScannedProduct.Nutriments, grams: Double) -> Double? {
        guard grams.isFinite, grams > 0, let value = per100g(nutrient, in: n) else { return nil }
        return value * grams / 100
    }

    /// True when the value is worked out rather than stated: unsaturated
    /// fat taken as fat minus saturated also holds the trans fat, so the
    /// card marks it as approximate.
    static func isEstimate(_ nutrient: Nutrient, in n: ScannedProduct.Nutriments) -> Bool {
        guard nutrient == .unsaturatedFat, per100g(nutrient, in: n) != nil else { return false }
        return statedUnsaturatedFat(in: n) == nil
    }

    /// The amount in a logged meal: known only when every food in it
    /// states it, since a missing food would make the total read low.
    static func amount(_ nutrient: Nutrient, in components: [MealFoodComponent]) -> Double? {
        MealFoodComponent.completeTotal(components.map { amount(nutrient, per100g: $0.per100g, grams: $0.grams) })
    }

    /// Label rounding: whole numbers from 10 up, one decimal below, so
    /// 0.4 g of saturated fat doesn't read as 0 and 412 mg of sodium
    /// doesn't read as 412.0.
    /// The value is first settled to two decimals so 4.3 × 1.5 (6.4499…
    /// in binary) reads 6.5 the way a person rounds it.
    static func formatted(_ value: Double, unit: Unit) -> String {
        let settled = (value * 100).rounded() / 100
        let digits = settled >= 10 || unit == .kilocalories ? 0...0 : 0...1
        let number = settled.formatted(.number.precision(.fractionLength(digits)).rounded(rule: .toNearestOrAwayFromZero))
        return "\(number) \(unit.rawValue)"
    }

    /// A stated value wins unless it and the saturated part together
    /// overrun the fat, which happens when they come from two sources.
    private static func unsaturatedFat(in n: ScannedProduct.Nutriments) -> Double? {
        statedUnsaturatedFat(in: n) ?? saturatedFat(in: n).map { n.fatG - $0 }
    }

    private static func statedUnsaturatedFat(in n: ScannedProduct.Nutriments) -> Double? {
        guard let stated = n.micros?.unsaturatedFatG, stated + (saturatedFat(in: n) ?? 0) <= n.fatG + 0.05 else { return nil }
        return stated
    }

    /// A saturated share above the fat it belongs to is a data-entry
    /// slip, so it is treated as unknown rather than shown impossible.
    private static func saturatedFat(in n: ScannedProduct.Nutriments) -> Double? {
        guard let saturated = n.micros?.saturatedFatG, saturated <= n.fatG + 0.05 else { return nil }
        return min(saturated, n.fatG)
    }
}
