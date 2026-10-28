import Foundation

/// One recipe from the bundled library (`recipe-library.json`). Unlike the
/// user's own `Recipe`, which points at foods in their library, this carries
/// its own per-serving nutrition, so it logs and ranks without any lookup.
/// Content ships in English and Swedish; pick with `localized(_:_:locale:)`.
struct LibraryRecipe: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let nameSV: String
    let category: MealCategory
    let mealPrep: Bool
    let minutes: Int
    /// Portions the recipe as written makes. Ingredient grams are per serving.
    let servings: Int
    /// Days a meal-prep box keeps in the fridge; nil for cook-and-eat recipes.
    let fridgeDays: Int?
    let tags: [String]
    let ingredients: [Ingredient]
    let steps: [String]
    let stepsSV: [String]
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let micros: Micros
    /// Asset-catalog name of the plated photo, `recipe-<id>`. May not exist yet.
    let image: String

    struct Ingredient: Codable, Hashable, Sendable {
        let name: String
        let nameSV: String
        /// Grams for one serving.
        let grams: Double
        /// Lowercase singular English name, the key the pantry stores.
        let pantryKey: String

        enum CodingKeys: String, CodingKey {
            case name, grams, pantryKey
            case nameSV = "name_sv"
        }
    }

    /// Per serving.
    struct Micros: Codable, Hashable, Sendable {
        let sodiumMg: Double
        let potassiumMg: Double
        let ironMg: Double
        let calciumMg: Double
        let vitaminDUg: Double
        let vitaminB12Ug: Double
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, mealPrep, minutes, servings, fridgeDays, tags, ingredients, steps
        case calories, proteinG, carbsG, fatG, fiberG, micros, image
        case nameSV = "name_sv"
        case stepsSV = "steps_sv"
    }

    var isHighProtein: Bool { tags.contains("high-protein") }

    /// Distinct pantry keys, in recipe order.
    var pantryKeys: [String] {
        var seen: Set<String> = []
        return ingredients.map(\.pantryKey).filter { seen.insert($0).inserted }
    }

    func displayName(locale: Locale) -> String {
        Self.isSwedish(locale) ? nameSV : name
    }

    func displaySteps(locale: Locale) -> [String] {
        Self.isSwedish(locale) && stepsSV.count == steps.count ? stepsSV : steps
    }

    static func isSwedish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "sv"
    }
}

extension LibraryRecipe.Ingredient {
    func displayName(locale: Locale) -> String {
        LibraryRecipe.isSwedish(locale) ? nameSV : name
    }
}
