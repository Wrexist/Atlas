import Foundation

/// Pure-function helpers for `UserProfile.recipes` — CRUD, lookup,
/// and the "fan a recipe out into a `LoggableMeal`" math that the
/// log-recipe path uses to compute totals.
///
/// The fan-out math intentionally re-resolves each component
/// against the current `customFoods` on every log so an edit to an
/// underlying food propagates without migrating the recipe. Recipe
/// ingredients are custom foods only; any other food ID is unresolved.
enum RecipeDataLogic {
    struct Review {
        let totals: LoggableMeal?
        let unresolved: [Recipe.Component]
    }

    /// Logging is all-or-nothing; partial preview totals are never loggable.
    static func review(for recipe: Recipe, customFoods: [CustomFood]) -> Review {
        let custom = Dictionary(customFoods.map { ($0.foodID, $0) }, uniquingKeysWith: { first, _ in first })
        let unresolved = recipe.components.filter { component in
            custom[component.foodID]?.toScannedProduct().loggable(for: component.portion) == nil
        }
        guard !recipe.components.isEmpty, unresolved.isEmpty else { return Review(totals: nil, unresolved: unresolved) }
        return Review(totals: totals(for: recipe, customFoods: customFoods), unresolved: [])
    }

    /// How many recipes use this food as an ingredient. Deleting the food
    /// leaves each of them unloggable until the ingredient is replaced.
    static func recipeCount(using foodID: String, in recipes: [Recipe]) -> Int {
        recipes.filter { recipe in recipe.components.contains { $0.foodID == foodID } }.count
    }

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

    /// Preview totals may omit unresolved ingredients. Logging must use `review`
    /// to require every ingredient and portion to resolve successfully.
    static func totals(for recipe: Recipe, customFoods: [CustomFood]) -> LoggableMeal {
        let customByID = Dictionary(customFoods.map { ($0.foodID, $0) }, uniquingKeysWith: { first, _ in first })
        var calories = 0, protein = 0, carbs = 0, fat = 0
        var snapshots: [MealFoodComponent] = []
        for component in recipe.components {
            guard let meal = customByID[component.foodID]?.toScannedProduct().loggable(for: component.portion) else {
                continue
            }
            calories += meal.calories
            protein += meal.proteinG
            carbs += meal.carbsG
            fat += meal.fatG
            if var snapshot = meal.components?.first {
                snapshot.id = component.id.uuidString
                snapshots.append(snapshot)
            }
        }
        return LoggableMeal(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat,
                           components: snapshots.count == recipe.components.count && !snapshots.isEmpty ? snapshots : nil)
    }
}
