import Foundation

/// Sums a day's vitamins and minerals from its logged foods and sets
/// each against an adult daily reference value.
enum MicronutrientEngine {

    enum Unit: String, Sendable {
        case milligrams = "mg"
        case micrograms = "µg"

        var symbol: String { rawValue }
    }

    enum Nutrient: String, CaseIterable, Identifiable, Sendable {
        case sodium, potassium, iron, calcium, vitaminD, vitaminB12

        var id: Self { self }

        var keyPath: KeyPath<Micronutrients, Double?> {
            switch self {
            case .sodium:     return \Micronutrients.sodiumMg
            case .potassium:  return \Micronutrients.potassiumMg
            case .iron:       return \Micronutrients.ironMg
            case .calcium:    return \Micronutrients.calciumMg
            case .vitaminD:   return \Micronutrients.vitaminDUg
            case .vitaminB12: return \Micronutrients.vitaminB12Ug
            }
        }

        var unit: Unit {
            switch self {
            case .sodium, .potassium, .iron, .calcium: .milligrams
            case .vitaminD, .vitaminB12:               .micrograms
            }
        }

        /// Adult reference intake per day, from the Nordic Nutrition
        /// Recommendations 2023 except iron, which uses the EU label
        /// reference (14 mg) as a middle ground between the men's and
        /// women's values. Sodium is the 5 g-of-salt ceiling (WHO, NNR).
        var dailyReference: Double {
            switch self {
            case .sodium:     2_000
            case .potassium:  3_500
            case .iron:       14
            case .calcium:    950
            case .vitaminD:   10
            case .vitaminB12: 4
            }
        }

        /// Sodium is a ceiling to stay under, not a target to reach.
        var isLimit: Bool { self == .sodium }
    }

    struct Intake: Hashable, Sendable {
        let nutrient: Nutrient
        /// Sum over the foods that state this nutrient; nil when none do.
        let total: Double?
        /// Foods (or legacy meals without food detail) that don't state it.
        let missing: Int

        /// Share of the daily reference, unclamped: 1.4 is 140 %.
        var fraction: Double? {
            total.map { $0 / nutrient.dailyReference }
        }

        var isOverLimit: Bool {
            nutrient.isLimit && (fraction ?? 0) > 1
        }
    }

    /// One nutrient summed over a day's meals. A meal logged without food
    /// detail counts as one missing food, like the fiber card does.
    static func intake(of nutrient: Nutrient, in entries: [MealEntry]) -> Intake {
        var values: [Double] = []
        var missing = 0
        for entry in entries {
            guard let foods = entry.components, !foods.isEmpty else { missing += 1; continue }
            for food in foods {
                if let value = food.micronutrient(nutrient.keyPath) { values.append(value) } else { missing += 1 }
            }
        }
        let total = values.reduce(0, +)
        return Intake(nutrient: nutrient, total: values.isEmpty || !total.isFinite ? nil : total, missing: missing)
    }

    /// Every tracked nutrient, in display order.
    static func dailyIntakes(_ entries: [MealEntry]) -> [Intake] {
        Nutrient.allCases.map { intake(of: $0, in: entries) }
    }
}
