import Foundation

/// Pure-function helpers for `UserProfile.recipes` — CRUD, lookup,
/// and the "fan a recipe out into a `LoggableMeal`" math that the
/// log-recipe path uses to compute totals.
///
/// The fan-out math intentionally re-resolves each component
/// against the current `customFoods` / barcode-cache state on
/// every log so an edit to an underlying food propagates without
/// migrating the recipe.
enum RecipeDataLogic {

    /// Inserts (or replaces by id) a recipe in the user's library.
    /// Newest-first sort by `updatedAt` so the list reads "what I
    /// just edited" on top.
    static func saveRecipe(into profile: inout UserProfile, recipe: Recipe) {
        var updated = recipe
        updated.updatedAt = Date()
        if let index = profile.recipes.firstIndex(where: { $0.id == recipe.id }) {
            profile.recipes[index] = updated
        } else {
            profile.recipes.append(updated)
        }
        profile.recipes.sort { $0.updatedAt > $1.updatedAt }
    }

    /// Removes one recipe by id. Idempotent.
    static func deleteRecipe(from profile: inout UserProfile, id: UUID) {
        profile.recipes.removeAll { $0.id == id }
    }

    /// Composite macro totals for a recipe. Iterates the components,
    /// resolves each foodID through the user's `customFoods` (and
    /// optionally a `cachedProductsByBarcode` map for OFF entries),
    /// and sums the per-component `loggable(for:)` outputs. Components
    /// whose food can't be resolved drop silently with a 0
    /// contribution — better than blocking the whole log because a
    /// custom food was deleted.
    static func totals(
        for recipe: Recipe,
        customFoods: [CustomFood],
        cachedProductsByBarcode: [String: ScannedProduct] = [:]
    ) -> LoggableMeal {
        let customByID: [String: CustomFood] = Dictionary(
            uniqueKeysWithValues: customFoods.map { ($0.foodID, $0) }
        )
        var calories = 0, protein = 0, carbs = 0, fat = 0
        for component in recipe.components {
            let product: ScannedProduct?
            if component.foodID.hasPrefix("custom:") {
                product = customByID[component.foodID]?.toScannedProduct()
            } else {
                product = cachedProductsByBarcode[component.foodID]
            }
            guard let product, let meal = product.loggable(for: component.portion) else {
                continue
            }
            calories += meal.calories
            protein += meal.proteinG
            carbs += meal.carbsG
            fat += meal.fatG
        }
        return LoggableMeal(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat)
    }
}
