import Foundation
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes the user's custom foods + favorites into Apple's
/// CoreSpotlight so they're searchable from device Spotlight, the
/// Lock Screen "Type to Search" pull-down, and the Siri suggestions
/// surface. A user searching "lasagna" in Spotlight gets their own
/// recipe back as a hit — tapping it opens Atlas. The route from
/// "tapped a Spotlight hit" to "logging that exact food" is a follow-
/// up (it needs a deep-link scheme through `PeptideApp`); for now
/// tapping just opens the app.
///
/// Pattern matches the other service singletons: `final class
/// : Sendable` with a `shared` accessor, idempotent index calls, and
/// errors logged but not propagated. CoreSpotlight tolerates writes
/// from any thread; the actor isolation lives in CSSearchableIndex
/// internally.
final class FoodSpotlightService: Sendable {

    static let shared = FoodSpotlightService()

    /// All indexed items get this domain — lets a future "clear all
    /// food-library entries" tap-out wipe in one call without
    /// touching peptide / protocol entries if those ever get indexed.
    static let domainIdentifier = "com.peptidesai.app.foodLibrary"

    private let index: CSSearchableIndex
    private let isAvailable: Bool

    init(index: CSSearchableIndex = .default()) {
        self.index = index
        self.isAvailable = CSSearchableIndex.isIndexingAvailable()
    }

    /// Full reindex of every custom food + favorited OFF product +
    /// recipe the user has. Called at app launch + on every food-
    /// library / recipe write so the Spotlight surface stays
    /// consistent with in-app state.
    ///
    /// Cheaper than the name implies — CoreSpotlight de-duplicates
    /// by uniqueIdentifier and the operation is async + transactional,
    /// so a re-index call during normal use is roughly a constant
    /// few hundred microseconds plus the kernel write.
    func reindex(profile: UserProfile, cachedFavorites: [ScannedProduct] = []) async {
        guard isAvailable else { return }

        var items: [CSSearchableItem] = []
        items.reserveCapacity(
            profile.customFoods.count + cachedFavorites.count + profile.recipes.count
        )

        for food in profile.customFoods {
            items.append(searchableItem(forCustomFood: food))
        }

        // OFF favorites need full `ScannedProduct` payloads to index
        // their names + brands. The Lifestyle layer assembles these
        // by reading `BarcodeProductCache`; passing them in avoids a
        // cross-actor hop from this service.
        for product in cachedFavorites where profile.favoriteFoodIDs.contains(product.barcode) {
            items.append(searchableItem(forFavorite: product))
        }

        for recipe in profile.recipes {
            items.append(searchableItem(forRecipe: recipe, customFoods: profile.customFoods))
        }

        guard !items.isEmpty else {
            // Nothing to index — clear out any stale entries so the
            // Spotlight surface doesn't outlive the data.
            try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
            return
        }

        do {
            // Replace-by-domain semantics: clear, then write. Avoids
            // an O(n) diff between what we have and what's already
            // indexed — Spotlight's own de-dup on uniqueIdentifier
            // would handle re-adds, but stale custom foods (deleted
            // in-app, still in the index) would linger.
            try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
            try await index.indexSearchableItems(items)
        } catch {
            AppLog.persistence.error(
                "Spotlight reindex failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Remove a specific custom food. Called from `DataStore.deleteCustomFood`
    /// so the Spotlight entry disappears the same moment the in-app
    /// list does — without it a user would see a search hit, tap, and
    /// land on a food that no longer exists.
    func removeCustomFood(id: UUID) async {
        guard isAvailable else { return }
        do {
            try await index.deleteSearchableItems(withIdentifiers: [Self.identifier(forCustomFoodID: id)])
        } catch {
            AppLog.persistence.error(
                "Spotlight removeCustomFood failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Item builders

    private func searchableItem(forCustomFood food: CustomFood) -> CSSearchableItem {
        // `UTType.content` is the documented umbrella type for
        // arbitrary in-app content; `UTType.text` mis-classified
        // foods as text snippets and caused some Spotlight surfaces
        // (e.g., the Lock-Screen suggestion strip) to render them
        // alongside notes / mail rather than as standalone hits.
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
        attributes.title = food.name
        attributes.contentDescription = Self.contentDescription(for: food.per100g)
        // `kind` shows as the "Type" label in Spotlight's preview
        // strip — set it to a stable string the user will recognise.
        attributes.kind = String(localized: "Custom food", comment: "Spotlight `Type` label for user-defined foods.")
        var keywords: [String] = [food.name]
        if let brand = food.brand, !brand.isEmpty {
            keywords.append(brand)
        }
        attributes.keywords = keywords
        return CSSearchableItem(
            uniqueIdentifier: Self.identifier(forCustomFoodID: food.id),
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }

    private func searchableItem(forRecipe recipe: Recipe, customFoods: [CustomFood]) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
        attributes.title = recipe.name
        let totals = RecipeDataLogic.totals(for: recipe, customFoods: customFoods)
        // Subtitle reads "Recipe · 3 ingredients · 420 kcal" so a
        // user searching "morning bowl" sees the macro shape
        // before tapping in. Keeps the Spotlight cell informative.
        attributes.contentDescription = String(
            localized: "Recipe · \(recipe.components.count) ingredients · \(totals.calories) kcal",
            comment: "Spotlight result subtitle for a recipe entry."
        )
        attributes.kind = String(localized: "Recipe", comment: "Spotlight `Type` label for a saved recipe.")
        // Index ingredient names too so a search for "oats" surfaces
        // every recipe that uses oats — useful when the user knows
        // an ingredient but not which recipe they're thinking of.
        var keywords: [String] = [recipe.name]
        keywords.append(contentsOf: recipe.components.map(\.cachedName))
        attributes.keywords = keywords
        return CSSearchableItem(
            uniqueIdentifier: Self.identifier(forRecipeID: recipe.id),
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }

    private func searchableItem(forFavorite product: ScannedProduct) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
        attributes.title = product.name
        attributes.contentDescription = Self.contentDescription(for: product.per100g)
        attributes.kind = String(localized: "Favorite food", comment: "Spotlight `Type` label for starred Open Food Facts products.")
        var keywords: [String] = [product.name]
        if let brand = product.brand, !brand.isEmpty {
            keywords.append(brand)
        }
        attributes.keywords = keywords
        // Deliberately don't set `thumbnailURL` from a remote OFF URL —
        // CSSearchableItemAttributeSet fetches it synchronously
        // server-side on index, which adds latency and depends on a
        // network round-trip. The OFF cache holds the image data
        // locally; a future enhancement could read the JPEG bytes
        // off disk and set `thumbnailData` instead. For v1, the
        // food-icon glyph the Spotlight default provides is fine.
        return CSSearchableItem(
            uniqueIdentifier: Self.identifier(forBarcode: product.barcode),
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }

    // MARK: - Identifier helpers

    /// Custom-food Spotlight IDs are scoped under `peptidex-food/custom/`
    /// so a future deep-link handler can pattern-match without
    /// confusing them with OFF favorites or other future entry types.
    static func identifier(forCustomFoodID id: UUID) -> String {
        "peptidex-food/custom/\(id.uuidString)"
    }

    /// OFF favorites are keyed by raw barcode so a Spotlight tap can
    /// hand the barcode straight to `OpenFoodFactsService.fetch(barcode:)`
    /// once deep-linking is wired.
    static func identifier(forBarcode barcode: String) -> String {
        "peptidex-food/off/\(barcode)"
    }

    /// Recipes get their own scheme so a future deep-link handler
    /// routes "tapped a Spotlight recipe" to the recipe-log
    /// confirm sheet rather than the food-review sheet — the two
    /// flows are different even though they both end in a meal log.
    static func identifier(forRecipeID id: UUID) -> String {
        "peptidex-food/recipe/\(id.uuidString)"
    }

    private static func contentDescription(for n: ScannedProduct.Nutriments) -> String {
        // Surfaced under the title in Spotlight results — quick macro
        // sniff so the user knows which entry is which when two have
        // similar names.
        String(
            localized: "\(Int(n.calories.rounded())) kcal, \(Int(n.proteinG.rounded()))g protein per 100g",
            comment: "Spotlight result subtitle. Surfaces calories + protein per 100 grams."
        )
    }
}
