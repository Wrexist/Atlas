import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes the user's custom foods + favorites into Apple's
/// CoreSpotlight so they're searchable from device Spotlight, the
/// Lock Screen "Type to Search" pull-down, and the Siri suggestions
/// surface. A user searching "lasagna" in Spotlight gets their own
/// recipe back as a hit — tapping it opens PeptideX. The route from
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

    /// Full reindex of every custom food + favorited OFF product the
    /// user has. Called at app launch + on every food-library write
    /// so the Spotlight surface stays consistent with in-app state.
    ///
    /// Cheaper than the name implies — CoreSpotlight de-duplicates by
    /// uniqueIdentifier and the operation is async + transactional,
    /// so a re-index call during normal use is roughly a constant
    /// few hundred microseconds plus the kernel write.
    func reindex(profile: UserProfile, cachedFavorites: [ScannedProduct] = []) async {
        guard isAvailable else { return }

        var items: [CSSearchableItem] = []
        items.reserveCapacity(profile.customFoods.count + cachedFavorites.count)

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
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        attributes.title = food.name
        attributes.contentDescription = Self.contentDescription(for: food.per100g)
        if let brand = food.brand, !brand.isEmpty {
            // Brand goes into both the supplementary subtitle and the
            // keyword set so a user searching "Mum" finds their
            // homemade lasagna by either name or attribution.
            attributes.supplementalContentType = brand
            attributes.keywords = [brand, food.name]
        } else {
            attributes.keywords = [food.name]
        }
        return CSSearchableItem(
            uniqueIdentifier: Self.identifier(forCustomFoodID: food.id),
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }

    private func searchableItem(forFavorite product: ScannedProduct) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        attributes.title = product.name
        attributes.contentDescription = Self.contentDescription(for: product.per100g)
        if let brand = product.brand, !brand.isEmpty {
            attributes.supplementalContentType = brand
            attributes.keywords = [brand, product.name]
        } else {
            attributes.keywords = [product.name]
        }
        if let url = product.imageURL {
            attributes.thumbnailURL = url
        }
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
