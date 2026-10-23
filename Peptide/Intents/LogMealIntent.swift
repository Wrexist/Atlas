import AppIntents

/// "Log my [Food]" — voice-driven food logging.
///
/// Resolves the chosen `FoodEntity` against the user's custom foods,
/// projects it through `CustomFood.toScannedProduct()`, and logs a
/// `MealEntry` at the default portion under the auto-detected meal
/// category (`MealCategory.auto(for: Date())`). For users who want
/// to log restaurant or branded foods this way, save them as
/// favorites in-app first — the entity query exposes whatever's
/// reachable from `profile.customFoods` so the surface stays
/// consistent with what the user explicitly opted into.
///
/// No portion or category parameters — voice users want one tap (or
/// one phrase). Power users wiring this into Shortcuts can still get
/// nuance through follow-up actions; the simple case stays simple.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log meal"

    static let description = IntentDescription(
        "Logs a meal using one of your custom foods. Uses the food's default portion and assigns the auto-detected meal category (Breakfast / Lunch / Dinner / Snack).",
        categoryName: "Nutrition"
    )

    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Food",
        description: "Which food to log.",
        requestValueDialog: IntentDialog("Which food?")
    )
    var food: FoodEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let foodID = food.id
        let resolution = await MainActor.run {
            Self.log(foodID: foodID, in: IntentDataStore.resolve(), at: Date())
        }

        switch resolution {
        case .notFound:
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "I couldn't find that food in your library. Save it in Atlas first.",
                    comment: "Siri response when the food entity can't be resolved (e.g. it was deleted)."
                )
            ))
        case .saveFailed:
            return .result(dialog: "The meal couldn't be saved. Open Atlas and retry.")
        case .logged(let name, let calories, let category):
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Logged \(name), \(calories) calories, under \(category.displayName).",
                    comment: "Siri confirmation after logging a meal. Name, kcal int, localized category name."
                )
            ))
        }
    }

    /// Logs the custom food at its default portion through the durable
    /// meal save, so Siri never confirms a meal that didn't persist.
    @MainActor
    static func log(foodID: String, in store: DataStore, at now: Date) -> Resolution {
        // We only support custom foods here — OFF favorites
        // need a cache lookup that may have been evicted, and
        // logging "stale" OFF data via voice surprises the user
        // when the macros don't match what they remember.
        guard foodID.hasPrefix("custom:"),
              let uuidString = foodID.split(separator: ":").last,
              let uuid = UUID(uuidString: String(uuidString)),
              let customFood = store.profile.customFoods.first(where: { $0.id == uuid })
        else {
            return .notFound
        }

        let product = customFood.toScannedProduct()
        guard let meal = product.loggable(for: product.defaultPortion) else {
            return .notFound
        }

        let category = MealCategory.auto(for: now)
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: category,
            source: .custom,
            sourceID: product.barcode,
            date: now
        )
        do {
            try store.commitScannedMeals([entry])
        } catch {
            return .saveFailed
        }
        store.flushPendingSave()
        return .logged(name: customFood.name, calories: meal.calories, category: category)
    }

    enum Resolution: Equatable {
        case logged(name: String, calories: Int, category: MealCategory)
        case notFound
        case saveFailed
    }
}
