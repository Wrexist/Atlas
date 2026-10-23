import Foundation

/// What the smart scanner thinks a photo or product is. Drives which
/// controls the review screen leads with — a packaged product gets the
/// whole-pack shortcut, a drink gets glass sizes, a meal gets portions.
enum FoodKind: String, Codable, Hashable, Sendable {
    case meal
    case packagedProduct = "packaged_product"
    case drink
    case ingredient
    case notFood = "not_food"

    var displayName: String {
        switch self {
        case .meal:            String(localized: "Meal", comment: "Smart scan result kind")
        case .packagedProduct: String(localized: "Packaged product", comment: "Smart scan result kind")
        case .drink:           String(localized: "Drink", comment: "Smart scan result kind")
        case .ingredient:      String(localized: "Ingredient", comment: "Smart scan result kind")
        case .notFood:         String(localized: "Not food", comment: "Smart scan result kind")
        }
    }

    var icon: String {
        switch self {
        case .meal:            "fork.knife"
        case .packagedProduct: "shippingbox.fill"
        case .drink:           "cup.and.saucer.fill"
        case .ingredient:      "carrot.fill"
        case .notFood:         "questionmark.circle"
        }
    }
}

/// A one-tap amount the scanner suggested for one specific food —
/// "2 slices", "pint 500 ml", "whole pack 400 g" — so correcting a
/// portion is a tap rather than arithmetic.
struct FoodPortionOption: Codable, Hashable, Sendable, Identifiable {
    let label: String
    let grams: Double
    var id: String { "\(label)|\(grams)" }
}

/// A typical-price range for an amount of food, in the user's currency.
/// Estimates, not receipts: the UI always shows them with "≈".
struct FoodPriceEstimate: Codable, Hashable, Sendable {
    enum Basis: String, Codable, Sendable {
        case store, restaurant, homemade
    }

    let low: Double
    let high: Double
    let currency: String
    let basis: Basis

    /// The same price for a different amount, assuming cost scales with
    /// weight. Used when the user re-portions a scanned item.
    func scaled(by factor: Double) -> FoodPriceEstimate? {
        guard factor.isFinite, factor > 0 else { return nil }
        return FoodPriceEstimate(low: low * factor, high: high * factor, currency: currency, basis: basis)
    }

    /// Sum of estimates that share a currency; nil when they don't, so
    /// a total never silently adds kronor to euros.
    static func total(_ prices: [FoodPriceEstimate]) -> FoodPriceEstimate? {
        guard let first = prices.first, prices.allSatisfy({ $0.currency == first.currency }) else { return nil }
        return FoodPriceEstimate(low: prices.reduce(0) { $0 + $1.low },
                                 high: prices.reduce(0) { $0 + $1.high },
                                 currency: first.currency, basis: first.basis)
    }

    /// "≈ 25–35 kr", or "≈ 30 kr" when the range rounds to one value.
    var formatted: String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency)
            .precision(.fractionLength(high < 10 ? 2 : 0))
        let lowText = low.formatted(style)
        let highText = high.formatted(style)
        return lowText == highText ? "≈ \(highText)" : "≈ \(lowText)–\(highText)"
    }

    /// Sane bounds for a single food: rejects negative, inverted and
    /// absurd ranges a confused model could produce.
    var isPlausible: Bool {
        low.isFinite && high.isFinite && low >= 0 && high >= low && high < 100_000
            && currency.count == 3
    }
}

/// The scan-level reading of a photo or product, shown above the
/// per-item rows: what it is, a one-line summary and the model's
/// specific tips ("frying oil isn't visible…").
struct ScanInsight: Codable, Hashable, Sendable {
    let kind: FoodKind
    let title: String
    let summary: String
    let tips: [String]
}

/// A one-tap question about a detail a photo can't show ("Fried in
/// oil?"). Every answer carries the item's complete values, so answering
/// recalculates on the spot without a second scan. The first answer is
/// the one the item's values already assume.
struct ScanQuestion: Codable, Hashable, Sendable {
    struct Answer: Codable, Hashable, Sendable {
        let label: String
        let grams: Double
        let per100g: ScannedProduct.Nutriments
    }

    let question: String
    let answers: [Answer]
}

/// Where a scanned item's values were checked against real data.
enum VerifiedFoodSource: String, Codable, Hashable, Sendable {
    case myFoods
    case openFoodFacts

    var displayName: String {
        switch self {
        case .myFoods:       String(localized: "From My Foods", comment: "Scanned item values come from the user's saved foods")
        case .openFoodFacts: String(localized: "Matched on Open Food Facts", comment: "Scanned item values were matched to an Open Food Facts entry")
        }
    }
}
