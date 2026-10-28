import Foundation
import OSLog

/// Loads the bundled recipe library and ranks it for "Recommended for you".
///
/// Pure and deterministic: every input (favourites, today's remaining
/// needs, the clock, recent meals, the pantry) is passed in, so the same
/// context always gives the same order. Ties break on the recipe id.
enum RecipeLibraryEngine {

    // MARK: - Loading

    /// The bundled library, decoded once per process.
    static let bundled: [LibraryRecipe] = load()

    static func load(bundle: Bundle = .main) -> [LibraryRecipe] {
        guard let url = bundle.url(forResource: "recipe-library", withExtension: "json") else {
            AppLog.database.error("RecipeLibraryEngine: recipe-library.json missing from bundle")
            return []
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            AppLog.database.error("RecipeLibraryEngine: decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func decode(_ data: Data) throws -> [LibraryRecipe] {
        try JSONDecoder().decode([LibraryRecipe].self, from: data)
    }

    // MARK: - Context

    /// Micronutrients a recipe can be "rich in". Sodium is left out: the
    /// day is never short of it in a way a recipe should fix.
    enum Micro: String, CaseIterable, Sendable {
        case potassium, iron, calcium, vitaminD, vitaminB12

        /// Nordic Nutrition Recommendations 2023 adult reference intake.
        var dailyReference: Double {
            switch self {
            case .potassium:  3500
            case .iron:       15
            case .calcium:    950
            case .vitaminD:   10
            case .vitaminB12: 4
            }
        }

        func amount(in micros: LibraryRecipe.Micros) -> Double {
            switch self {
            case .potassium:  micros.potassiumMg
            case .iron:       micros.ironMg
            case .calcium:    micros.calciumMg
            case .vitaminD:   micros.vitaminDUg
            case .vitaminB12: micros.vitaminB12Ug
            }
        }

        var displayName: String {
            switch self {
            case .potassium:  String(localized: "potassium", comment: "Micronutrient in a recipe reason, e.g. 'Rich in potassium'")
            case .iron:       String(localized: "iron", comment: "Micronutrient in a recipe reason")
            case .calcium:    String(localized: "calcium", comment: "Micronutrient in a recipe reason")
            case .vitaminD:   String(localized: "vitamin D", comment: "Micronutrient in a recipe reason")
            case .vitaminB12: String(localized: "vitamin B12", comment: "Micronutrient in a recipe reason")
            }
        }
    }

    /// What is left of today's targets. Fibre and micronutrients are
    /// optional: without them the ranking simply skips those bonuses.
    struct Needs: Hashable, Sendable {
        var remainingCalories: Int
        var remainingProteinG: Int
        var remainingFiberG: Double?
        var lowMicros: Set<Micro> = []
    }

    struct Context: Sendable {
        /// Names of the user's favourite foods, in whatever language they were saved.
        var favoriteFoodNames: [String] = []
        var needs: Needs?
        var now: Date
        var calendar: Calendar
        /// Lowercased names of meals logged in the last few days.
        var recentMealNames: Set<String> = []
        /// Pantry keys the user has at home.
        var pantry: Set<String> = []
    }

    enum Reason: Hashable, Sendable {
        case favorites([LibraryRecipe.Ingredient])
        case pantry(have: Int, total: Int)
        case highProtein
        case fitsCalories(remaining: Int)
        case fiber
        case micro(Micro)
        case timeOfDay(MealCategory)
    }

    struct Recommendation: Hashable, Identifiable, Sendable {
        let recipe: LibraryRecipe
        let score: Double
        /// Most persuasive first.
        let reasons: [Reason]
        var id: String { recipe.id }
    }

    // MARK: - Ranking

    static let recentWindowDays = 3
    static let favoriteBonus = 10.0
    static let favoriteCap = 25.0
    static let timeOfDayBonus = 15.0
    static let recentPenalty = 20.0
    static let pantryThreshold = 0.6
    /// Snacks this far over the remaining calories still count as fitting.
    static let calorieSlack = 50

    static func recommend(_ recipes: [LibraryRecipe], context: Context, limit: Int = 8) -> [Recommendation] {
        let favoriteWords = favoriteWordSet(context.favoriteFoodNames)
        let slot = MealCategory.auto(for: context.now, calendar: context.calendar)
        return recipes
            .map { recommendation(for: $0, context: context, favoriteWords: favoriteWords, slot: slot) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.recipe.id < $1.recipe.id }
            .prefix(limit)
            .map { $0 }
    }

    static func recommendation(for recipe: LibraryRecipe, context: Context) -> Recommendation {
        recommendation(
            for: recipe,
            context: context,
            favoriteWords: favoriteWordSet(context.favoriteFoodNames),
            slot: MealCategory.auto(for: context.now, calendar: context.calendar)
        )
    }

    private static func recommendation(
        for recipe: LibraryRecipe,
        context: Context,
        favoriteWords: Set<String>,
        slot: MealCategory
    ) -> Recommendation {
        var score = 0.0
        var reasons: [Reason] = []

        let favorites = favoriteIngredients(in: recipe, favoriteWords: favoriteWords)
        if !favorites.isEmpty {
            score += min(favoriteCap, favoriteBonus * Double(favorites.count))
            reasons.append(.favorites(favorites))
        }

        let coverage = pantryCoverage(recipe, pantry: context.pantry)
        if coverage.total > 0 {
            let share = Double(coverage.have) / Double(coverage.total)
            if share >= pantryThreshold {
                score += 20 * share
                reasons.append(.pantry(have: coverage.have, total: coverage.total))
            }
        }

        // Baseline health: protein density, so the library leans high-protein
        // even before targets exist.
        let proteinShare = recipe.proteinG * 4 / Double(max(1, recipe.calories))
        score += 10 * min(proteinShare, 0.4)
        if let needs = context.needs {
            score += needsScore(recipe, needs: needs, reasons: &reasons)
        } else if recipe.isHighProtein {
            reasons.append(.highProtein)
        }

        if recipe.category == slot {
            score += timeOfDayBonus
        }

        if wasEatenRecently(recipe, recentNames: context.recentMealNames) {
            score -= recentPenalty
        }

        if reasons.isEmpty { reasons.append(.timeOfDay(recipe.category)) }
        return Recommendation(recipe: recipe, score: score, reasons: reasons)
    }

    private static func needsScore(_ recipe: LibraryRecipe, needs: Needs, reasons: inout [Reason]) -> Double {
        var score = 0.0

        let proteinNeed = max(0, needs.remainingProteinG)
        if proteinNeed > 0 {
            score += 20 * min(1, recipe.proteinG / Double(proteinNeed))
            if recipe.isHighProtein { reasons.append(.highProtein) }
        }

        let calorieRoom = max(0, needs.remainingCalories)
        let overshoot = recipe.calories - calorieRoom
        if overshoot > calorieSlack {
            score -= min(40, Double(overshoot) / 10)
        } else if calorieRoom > 0 {
            score += 10
            reasons.append(.fitsCalories(remaining: calorieRoom))
        }

        let fiberRoom = needs.remainingFiberG ?? 0
        if recipe.fiberG >= 8 {
            score += fiberRoom > 10 ? 10 : 5
            if fiberRoom > 10 { reasons.append(.fiber) }
        }

        let rich = Micro.allCases.filter { needs.lowMicros.contains($0) && isRich(recipe, in: $0) }
        score += min(12, 6 * Double(rich.count))
        if let first = rich.first { reasons.append(.micro(first)) }

        return score
    }

    /// A serving gives at least a fifth of the daily reference.
    static func isRich(_ recipe: LibraryRecipe, in micro: Micro) -> Bool {
        micro.amount(in: recipe.micros) >= micro.dailyReference * 0.2
    }

    // MARK: - Favourites

    /// Words that name a form or brand, not a food, so "chicken breast"
    /// doesn't match "turkey breast".
    private static let stopWords: Set<String> = [
        "breast", "fillet", "filé", "fresh", "färsk", "frozen", "fryst", "frysta", "natural", "naturell",
        "plain", "light", "lätt", "mixed", "blandade", "baby", "whole", "in", "with", "med", "och", "and",
        "water", "vatten", "sauce", "sås", "powder", "oil", "olja", "the", "red", "röda", "green", "gröna",
    ]

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private static func favoriteWordSet(_ names: [String]) -> Set<String> {
        Set(names.flatMap(words))
    }

    /// Ingredients whose English, Swedish or pantry name shares a word
    /// with a favourite food. Words match whole, or one starts with the
    /// other ("kyckling" ~ "kycklingfilé", "lax" ~ "laxfilé").
    static func favoriteIngredients(in recipe: LibraryRecipe, favoriteNames: [String]) -> [LibraryRecipe.Ingredient] {
        favoriteIngredients(in: recipe, favoriteWords: favoriteWordSet(favoriteNames))
    }

    private static func favoriteIngredients(in recipe: LibraryRecipe, favoriteWords: Set<String>) -> [LibraryRecipe.Ingredient] {
        guard !favoriteWords.isEmpty else { return [] }
        var seen: Set<String> = []
        return recipe.ingredients.filter { ingredient in
            let ingredientWords = words("\(ingredient.pantryKey) \(ingredient.name) \(ingredient.nameSV)")
            let matches = ingredientWords.contains { word in
                favoriteWords.contains { wordsMatch($0, word) }
            }
            return matches && seen.insert(ingredient.pantryKey).inserted
        }
    }

    private static func wordsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }

    /// Favourite IDs are OFF barcodes or `custom:<uuid>`. Custom foods carry
    /// their name; a barcode's name comes from the last meal logged from it.
    static func favoriteFoodNames(
        favoriteIDs: Set<String>,
        customFoods: [CustomFood],
        mealHistory: [MealEntry]
    ) -> [String] {
        guard !favoriteIDs.isEmpty else { return [] }
        var names: [String: String] = [:]
        for food in customFoods where favoriteIDs.contains(food.foodID) {
            names[food.foodID] = food.name
        }
        for meal in mealHistory.sorted(by: { $0.date < $1.date }) {
            guard let id = meal.sourceID, favoriteIDs.contains(id), !id.hasPrefix("custom:") else { continue }
            names[id] = meal.name
        }
        return names.keys.sorted().compactMap { names[$0] }
    }

    // MARK: - Variety

    static func recentMealNames(in mealHistory: [MealEntry], now: Date, calendar: Calendar) -> Set<String> {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -recentWindowDays, to: today) else { return [] }
        return Set(mealHistory.filter { $0.date >= start && $0.date <= now }.map { $0.name.lowercased() })
    }

    static func wasEatenRecently(_ recipe: LibraryRecipe, recentNames: Set<String>) -> Bool {
        recentNames.contains(recipe.name.lowercased()) || recentNames.contains(recipe.nameSV.lowercased())
    }

    // MARK: - Pantry

    static func pantryCoverage(_ recipe: LibraryRecipe, pantry: Set<String>) -> (have: Int, total: Int) {
        let keys = recipe.pantryKeys
        return (keys.filter(pantry.contains).count, keys.count)
    }

    // MARK: - Servings

    static func grams(_ ingredient: LibraryRecipe.Ingredient, servings: Int) -> Double {
        ingredient.grams * Double(max(1, servings))
    }

    /// Whole grams under 100, rounded to 5 g above, so a scaled list
    /// reads "450 g" rather than "447.5 g".
    static func displayGrams(_ grams: Double) -> Int {
        grams < 100 ? Int(grams.rounded()) : Int((grams / 5).rounded()) * 5
    }

    // MARK: - Reason text

    /// The first two reasons joined with " · ", e.g.
    /// "High protein · Fits your 640 kcal left".
    static func reasonText(_ reasons: [Reason], locale: Locale) -> String {
        reasons.prefix(2).map { text(for: $0, locale: locale) }.joined(separator: " · ")
    }

    static func text(for reason: Reason, locale: Locale) -> String {
        switch reason {
        case .favorites(let ingredients):
            let names = ingredients.prefix(2).map { $0.displayName(locale: locale).lowercased() }
            let list = names.joined(separator: ", ")
            return String(localized: "With your favourites: \(list)", comment: "Recipe recommendation reason; the list names favourite ingredients")
        case .pantry(let have, let total):
            return String(localized: "\(have) of \(total) at home", comment: "Recipe recommendation reason: ingredients the user has at home")
        case .highProtein:
            return String(localized: "High protein", comment: "Recipe recommendation reason")
        case .fitsCalories(let remaining):
            return String(localized: "Fits your \(remaining) kcal left", comment: "Recipe recommendation reason: the recipe fits the calories left today")
        case .fiber:
            return String(localized: "Rich in fibre", comment: "Recipe recommendation reason")
        case .micro(let micro):
            return String(localized: "Rich in \(micro.displayName)", comment: "Recipe recommendation reason, e.g. 'Rich in iron'")
        case .timeOfDay(let category):
            switch category {
            case .breakfast: return String(localized: "A good start to the day", comment: "Recipe recommendation reason for breakfast")
            case .lunch:     return String(localized: "Made for lunch", comment: "Recipe recommendation reason for lunch")
            case .dinner:    return String(localized: "Tonight's dinner", comment: "Recipe recommendation reason for dinner")
            case .snack:     return String(localized: "A smart snack", comment: "Recipe recommendation reason for a snack")
            }
        }
    }

    // MARK: - Logging

    /// One serving as a diary entry. The dish is one component so its
    /// fibre reaches the day's totals.
    static func entry(for recipe: LibraryRecipe, locale: Locale, at date: Date, calendar: Calendar) -> MealEntry {
        let grams = recipe.ingredients.reduce(0) { $0 + $1.grams }
        let per100 = 100 / max(1, grams)
        let component = MealFoodComponent(
            id: "recipe:\(recipe.id)",
            name: recipe.displayName(locale: locale),
            grams: grams,
            servingGrams: grams,
            servingLabel: nil,
            per100g: ScannedProduct.Nutriments(
                calories: Double(recipe.calories) * per100,
                proteinG: recipe.proteinG * per100,
                carbsG: recipe.carbsG * per100,
                fatG: recipe.fatG * per100,
                fiberG: recipe.fiberG * per100,
                sugarsG: nil
            ),
            sourceID: nil
        )
        return MealEntry(
            date: date,
            category: recipe.category == .snack ? .snack : MealCategory.auto(for: date, calendar: calendar),
            name: recipe.displayName(locale: locale),
            calories: recipe.calories,
            proteinG: Int(recipe.proteinG.rounded()),
            carbsG: Int(recipe.carbsG.rounded()),
            fatG: Int(recipe.fatG.rounded()),
            source: .manual,
            components: [component]
        )
    }
}
