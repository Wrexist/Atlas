import AppIntents

/// "Log my morning bowl" — voice-driven recipe logging.
///
/// Resolves the chosen `RecipeEntity` to the live `Recipe`,
/// composes the macro totals via `RecipeDataLogic`, and writes a
/// single `MealEntry` named after the recipe under the auto-
/// detected meal category. One Siri phrase → composed multi-
/// ingredient meal in one tap.
///
/// No category parameter — the auto-pick is the right default for
/// a voice surface; users who want to override pick the recipe
/// in-app and tap once on the confirm sheet.
struct LogRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log recipe"

    static let description = IntentDescription(
        "Logs a saved recipe — every component's macros sum into one meal entry under the auto-detected meal category.",
        categoryName: "Nutrition"
    )

    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Recipe",
        description: "Which saved recipe to log.",
        requestValueDialog: IntentDialog("Which recipe?")
    )
    var recipe: RecipeEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recipeID = recipe.id

        let outcome: Outcome = await MainActor.run {
            let store = IntentDataStore.resolve()
            guard let uuid = UUID(uuidString: recipeID),
                  let target = store.profile.recipes.first(where: { $0.id == uuid })
            else {
                return .notFound
            }

            let totals = RecipeDataLogic.totals(
                for: target,
                customFoods: store.profile.customFoods
            )
            guard totals.calories > 0 else {
                return .empty
            }

            let now = Date()
            let category = MealCategory.auto(for: now)
            store.logRecipe(target, category: category, at: now)
            store.flushPendingSave()
            return .logged(name: target.name, calories: totals.calories, category: category)
        }

        switch outcome {
        case .notFound:
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "I couldn't find that recipe in your library.",
                    comment: "Siri response when the recipe entity can't be resolved."
                )
            ))
        case .empty:
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "That recipe doesn't add up to any calories — open Atlas to fix the ingredient list.",
                    comment: "Siri response when a recipe sums to zero (every component food was deleted)."
                )
            ))
        case .logged(let name, let calories, let category):
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Logged \(name), \(calories) calories, under \(category.displayName).",
                    comment: "Siri confirmation after logging a recipe."
                )
            ))
        }
    }

    private enum Outcome {
        case logged(name: String, calories: Int, category: MealCategory)
        case notFound
        case empty
    }
}
