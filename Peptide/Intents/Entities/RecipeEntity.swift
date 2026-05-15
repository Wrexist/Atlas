import AppIntents

/// App Intents projection of a saved `Recipe`. Surfaces every
/// recipe in the user's library so Siri can match "Log my morning
/// bowl" against a real entity. Composite-calorie subtitle reads
/// at the parameter-pick step so the user can disambiguate two
/// similarly-named recipes by macros.
struct RecipeEntity: AppEntity, Identifiable {
    let id: String        // recipe UUID string
    let displayName: String
    let calorieSummary: Int
    let ingredientCount: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Recipe", comment: "App Intents — type name for one recipe entity"),
            numericFormat: LocalizedStringResource("\(placeholder: .int) recipes")
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(ingredientCount) ingredients · \(calorieSummary) kcal"
        )
    }

    static var defaultQuery = RecipeEntityQuery()
}

struct RecipeEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RecipeEntity] {
        let all = await MainActor.run {
            let store = IntentDataStore.resolve()
            return Self.allEntities(in: store)
        }
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { lookup[$0] }
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        await MainActor.run {
            let store = IntentDataStore.resolve()
            return Self.allEntities(in: store)
        }
    }

    /// Siri NL match. Recipe names are user-defined ("morning bowl",
    /// "post-workout shake"), so case-insensitive containment match
    /// against the stored name is the right shape — no fuzzy
    /// stemming needed when the corpus is one user's own library.
    func entities(matching string: String) async throws -> [RecipeEntity] {
        let needle = string.lowercased()
        let all = await MainActor.run {
            let store = IntentDataStore.resolve()
            return Self.allEntities(in: store)
        }
        return all.filter { $0.displayName.lowercased().contains(needle) }
    }

    @MainActor
    private static func allEntities(in store: DataStore) -> [RecipeEntity] {
        store.profile.recipes.map { recipe in
            let totals = RecipeDataLogic.totals(
                for: recipe,
                customFoods: store.profile.customFoods
            )
            return RecipeEntity(
                id: recipe.id.uuidString,
                displayName: recipe.name,
                calorieSummary: totals.calories,
                ingredientCount: recipe.components.count
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
