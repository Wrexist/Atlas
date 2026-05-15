import Foundation

/// A user-defined food the food-library can surface alongside Open
/// Food Facts results. Lets users log items they can't scan and the
/// public database doesn't carry (their grandmother's stew, the
/// unbranded snack from the corner shop, an in-house meal-prep mix).
///
/// Macros are stored per-100g so the same portion math the OFF flow
/// uses applies unmodified — `toScannedProduct()` projects this into
/// the existing `ScannedProduct` shape so the review/log UI never
/// branches on data origin.
struct CustomFood: Codable, Hashable, Identifiable, Sendable {

    /// Stable identifier used both as the SwiftData primary key (when
    /// we later migrate) and to derive the synthetic `custom:<uuid>`
    /// food ID used for favorites and recents. UUID rather than an
    /// auto-incrementing int so duplicates can't collide across
    /// devices that sync via CloudKit.
    let id: UUID

    var name: String

    /// Optional brand/source label ("Trader Joe's", "Mum's recipe").
    /// Shown as a subtitle on the result row; not used in any
    /// computation.
    var brand: String?

    /// Macros per 100 grams of the food, mirroring
    /// `ScannedProduct.Nutriments`. Storing per-100g keeps the math
    /// uniform with OFF — portion math is one multiplication away
    /// regardless of whether the user logs 50 g or 1.5 servings.
    var per100g: ScannedProduct.Nutriments

    /// Grams in one "serving" as the user defines it. Optional because
    /// many home recipes don't have a meaningful serving — fall back to
    /// the grams-based picker in the review sheet.
    var servingGrams: Double?

    /// Free-form serving label printed in the review sheet ("1 cup",
    /// "1 slice"). Pure UI hint — the math uses `servingGrams`.
    var servingLabel: String?

    /// Stamp on create / edit. Used to sort the "My Foods" tab so the
    /// food you just added lands at the top.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        per100g: ScannedProduct.Nutriments,
        servingGrams: Double? = nil,
        servingLabel: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.per100g = per100g
        self.servingGrams = servingGrams
        self.servingLabel = servingLabel
        self.updatedAt = updatedAt
    }
}

extension CustomFood {

    /// `custom:<uuid>` namespaced ID used by the favorites set and the
    /// recents history. Distinct from OFF's numeric barcodes so the
    /// two can coexist in the same dictionaries without collision.
    var foodID: String { "custom:\(id.uuidString)" }

    /// Project into a `ScannedProduct` so the review/portion-picker
    /// sheet stays single-source. The synthetic `foodID` is passed as
    /// the barcode; downstream code that round-trips IDs back to a
    /// concrete food matches against the `custom:` prefix.
    func toScannedProduct(fetchedAt: Date = Date()) -> ScannedProduct {
        ScannedProduct(
            barcode: foodID,
            name: name,
            brand: brand?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
            imageURL: nil,
            servingSizeText: servingLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
            servingGrams: servingGrams.flatMap { $0 > 0 ? $0 : nil },
            packageGrams: nil,
            per100g: per100g,
            nutriScore: nil,
            novaGroup: nil,
            fetchedAt: fetchedAt
        )
    }
}

extension CustomFood {
    /// Default macros surfaced in the editor when the user first opens
    /// it. Every value is zero — the editor relies on inline validation
    /// to require at least a name and a calorie value before saving.
    static var blank: CustomFood {
        CustomFood(
            name: "",
            per100g: ScannedProduct.Nutriments(
                calories: 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                fiberG: nil,
                sugarsG: nil
            )
        )
    }
}

