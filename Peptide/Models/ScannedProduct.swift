import Foundation

/// A packaged-food product resolved from a barcode lookup, normalized to
/// per-100g nutrition so portion math is one multiplication away.
///
/// Open Food Facts and other databases are inconsistent about which
/// fields they expose — some products have only per-serving values,
/// others only per-100g. `OpenFoodFactsService` rounds-trips into this
/// canonical shape so the UI layer never branches on data-source quirks.
struct ScannedProduct: Codable, Hashable, Sendable {

    /// The raw barcode the user scanned (digits only).
    let barcode: String

    /// Display name. Falls back to the brand or "Unknown product" when
    /// the upstream record is missing a product name.
    let name: String

    let brand: String?

    let imageURL: URL?

    /// Free-form serving label as printed on the package ("330 ml",
    /// "1 cookie (28 g)"). Shown in the portion picker as a hint.
    let servingSizeText: String?

    /// Grams in one serving, when known. Drives the "× servings" stepper.
    let servingGrams: Double?

    /// Grams in the whole package, when known. Drives the "log whole
    /// package" shortcut.
    let packageGrams: Double?

    /// Macronutrients per 100 grams of the product. Always populated —
    /// missing upstream fields collapse to 0 so portion math is total.
    let per100g: Nutriments

    /// Open Food Facts Nutri-Score letter (a–e). Optional metadata for
    /// the review card; not used in any computation.
    let nutriScore: String?

    /// NOVA processing classification (1–4). Optional metadata.
    let novaGroup: Int?

    /// ISO 8601 timestamp the upstream record was fetched. Stamped by
    /// the service so callers can show a "data updated" hint.
    let fetchedAt: Date
}

extension ScannedProduct {

    struct Nutriments: Codable, Hashable, Sendable {
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double?
        let sugarsG: Double?

        static let zero = Nutriments(
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: nil, sugarsG: nil
        )
    }

    /// How the user wants to log a portion of this product. The three
    /// modes are mutually exclusive — the UI shows whichever one is
    /// active and recalculates macros live as the user adjusts it.
    enum Portion: Hashable, Sendable {
        /// A raw weight in grams. Anchored to the per-100g nutrients.
        case grams(Double)
        /// A count of label servings. Requires `servingGrams` upstream.
        case servings(Double)
        /// The entire package. Requires `packageGrams` upstream.
        case wholePackage
    }

    /// Macros rounded to the integer shape `DataStore.logMeal(...)`
    /// expects. Returns nil when the requested portion mode needs a
    /// field the product doesn't have (e.g. `.servings` on a product
    /// with no per-serving weight).
    func loggable(for portion: Portion) -> LoggableMeal? {
        guard let grams = grams(for: portion), grams > 0 else { return nil }
        let multiplier = grams / 100.0
        return LoggableMeal(
            calories: roundedNonNegative(per100g.calories * multiplier),
            proteinG: roundedNonNegative(per100g.proteinG * multiplier),
            carbsG:   roundedNonNegative(per100g.carbsG * multiplier),
            fatG:     roundedNonNegative(per100g.fatG * multiplier)
        )
    }

    /// Resolves a portion mode to a concrete weight in grams, or nil
    /// when the product is missing the field that mode depends on.
    func grams(for portion: Portion) -> Double? {
        switch portion {
        case .grams(let g):       return g
        case .servings(let s):    return servingGrams.map { $0 * s }
        case .wholePackage:       return packageGrams
        }
    }

    /// The portion mode the UI should preselect, applied in priority
    /// order: a known serving size, else the whole package when it's a
    /// reasonable single-meal size, else 100 g as the safe default.
    var defaultPortion: Portion {
        if servingGrams != nil { return .servings(1) }
        if let pkg = packageGrams, pkg <= 500 { return .wholePackage }
        return .grams(100)
    }


    private func roundedNonNegative(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(value.rounded())
    }
}

extension ScannedProduct.Portion {
    /// Canonical case-discriminator helpers. Previously BarcodeScanFlow
    /// and FoodLibraryFlow each carried a private file-scoped
    /// extension with the same logic under slightly different names
    /// (`isServings` vs `isServingsCase`). Consolidated here so the
    /// two scanners read from the same source.
    var isServings: Bool {
        if case .servings = self { return true }
        return false
    }

    var isGrams: Bool {
        if case .grams = self { return true }
        return false
    }
}

/// Integer-rounded macros in the exact shape `DataStore.logMeal(...)`
/// accepts. Decoupled from `MealScannerService.MealEstimate` because the
/// barcode flow doesn't have a confidence score or model-generated name.
struct LoggableMeal: Hashable, Sendable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
}
