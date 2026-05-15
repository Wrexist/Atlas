import AppIntents

/// App Intents projection of a loggable food. Surfaces every custom
/// food the user has saved plus every favorited OFF product so
/// "Log my overnight oats" / "Log Fage 0%" resolve via Siri.
///
/// Identifier uses the same `custom:<uuid>` / barcode scheme
/// `MealEntry.sourceID` and `FoodSpotlightService` use, so a future
/// "log my last meal again" pipeline can round-trip the same id
/// without ambiguity.
struct FoodEntity: AppEntity, Identifiable {
    let id: String                  // `custom:<uuid>` or raw OFF barcode
    let displayName: String
    let subtitle: String?
    let caloriesPer100g: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Food", comment: "App Intents — type name for one food entity"),
            numericFormat: LocalizedStringResource("\(placeholder: .int) foods")
        )
    }

    var displayRepresentation: DisplayRepresentation {
        if let subtitle, !subtitle.isEmpty {
            return DisplayRepresentation(
                title: "\(displayName)",
                subtitle: "\(subtitle)"
            )
        }
        return DisplayRepresentation(title: "\(displayName)")
    }

    static var defaultQuery = FoodEntityQuery()
}

struct FoodEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [FoodEntity] {
        let all = await MainActor.run {
            let store = IntentDataStore.resolve()
            return Self.allEntities(in: store)
        }
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { lookup[$0] }
    }

    func suggestedEntities() async throws -> [FoodEntity] {
        await MainActor.run {
            let store = IntentDataStore.resolve()
            return Self.allEntities(in: store)
        }
    }

    /// Siri NL pipeline calls this with the spoken term ("oatmeal").
    /// We match against display name + subtitle, lowercased, so
    /// brand-prefixed queries ("Trader Joe's oat") still find their
    /// match even when the user only said part of the name.
    func entities(matching string: String) async throws -> [FoodEntity] {
        let needle = string.lowercased()
        let all = await MainActor.run {
            let store = IntentDataStore.resolve()
            return Self.allEntities(in: store)
        }
        return all.filter { entity in
            entity.displayName.lowercased().contains(needle)
                || (entity.subtitle?.lowercased().contains(needle) ?? false)
        }
    }

    /// Walks profile.customFoods + cached favorites and projects into
    /// `FoodEntity`. OFF favorites that have been evicted from the
    /// barcode cache are dropped silently — there's nothing to read
    /// back if we don't have the product details.
    @MainActor
    private static func allEntities(in store: DataStore) -> [FoodEntity] {
        var out: [FoodEntity] = []
        out.reserveCapacity(store.profile.customFoods.count)

        for food in store.profile.customFoods {
            out.append(FoodEntity(
                id: food.foodID,
                displayName: food.name,
                subtitle: food.brand,
                caloriesPer100g: Int(food.per100g.calories.rounded())
            ))
        }
        // Sort alphabetically — Shortcuts picker is a list and a
        // stable order beats "whatever insertion order happens to be".
        return out.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
