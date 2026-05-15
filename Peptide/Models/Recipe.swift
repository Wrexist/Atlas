import Foundation

/// A named combination of one or more foods. Lets users log a
/// composite meal in a single tap — "morning bowl = 80g oats +
/// 1 banana + 1 scoop whey + 200g blueberries" becomes one
/// `Recipe` named "Morning bowl" that, when logged, fans out to
/// the right macros.
///
/// Every component carries its own portion override + foodID
/// reference so the macros are computed from the live food data
/// at log time. Editing a custom food (raising the calories on
/// "whey scoop" from 110 to 120) automatically updates every
/// recipe that includes it the next time the user logs it.
struct Recipe: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// Optional one-line description shown under the name in the
    /// list ("Saturday breakfast", "post-workout", "meal prep").
    var note: String?
    /// Components in the order the user added them. UI can preserve
    /// the order when rendering the macro breakdown so the user
    /// recognises their own list.
    var components: [Component]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        note: String? = nil,
        components: [Component] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.components = components
        self.updatedAt = updatedAt
    }

    /// One ingredient line in the recipe. Keyed by the food's
    /// stable `foodID` (custom: prefix or OFF barcode) so a future
    /// food rename / macro edit propagates automatically the next
    /// time the recipe is logged.
    struct Component: Codable, Hashable, Identifiable, Sendable {
        let id: UUID
        /// Either `custom:<uuid>` for a CustomFood or a raw OFF
        /// barcode. Resolved at log time via the same lookup the
        /// food library uses.
        var foodID: String
        /// Cached display name as it was when the user added the
        /// component. Used as a fallback if the underlying food has
        /// since been deleted; the macro math falls through to nil
        /// in that case so the row reads "Unknown food".
        var cachedName: String
        /// Portion mode — same shape as `ScannedProduct.Portion`.
        var portion: ScannedProduct.Portion

        init(
            id: UUID = UUID(),
            foodID: String,
            cachedName: String,
            portion: ScannedProduct.Portion
        ) {
            self.id = id
            self.foodID = foodID
            self.cachedName = cachedName
            self.portion = portion
        }
    }
}
