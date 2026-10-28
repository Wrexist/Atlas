import Foundation

/// Turns a meal plan into a shopping list: one row per ingredient, the
/// same ingredient merged across meals and days, amounts summed per
/// dimension (mass in g, volume in ml, else portions), and every row
/// filed under a store section by a Swedish + English keyword map.
///
/// The meal plan is a single planned day, so a list for N days is that
/// day's ingredients times N.
enum GroceryListEngine {

    enum Section: String, CaseIterable, Hashable, Identifiable, Sendable {
        case produce, dairy, meatFish, pantry, frozen, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .produce:  String(localized: "Fruit & veg")
            case .dairy:    String(localized: "Dairy")
            case .meatFish: String(localized: "Meat & fish")
            case .pantry:   String(localized: "Pantry")
            case .frozen:   String(localized: "Frozen")
            case .other:    String(localized: "Other")
            }
        }

        var icon: String {
            switch self {
            case .produce:  "carrot.fill"
            case .dairy:    "cup.and.saucer.fill"
            case .meatFish: "fish.fill"
            case .pantry:   "takeoutbag.and.cup.and.straw.fill"
            case .frozen:   "snowflake"
            case .other:    "basket.fill"
            }
        }
    }

    /// Units an ingredient can arrive in.
    enum Unit: String, CaseIterable, Hashable, Sendable {
        case g, kg, ml, cl, dl, l, portion

        var measure: Measure {
            switch self {
            case .g, .kg: .mass
            case .ml, .cl, .dl, .l: .volume
            case .portion: .portions
            }
        }

        /// Multiplier into the measure's base unit (g, ml, portions).
        var toBase: Double {
            switch self {
            case .g, .ml, .portion: 1
            case .cl: 10
            case .dl: 100
            case .kg, .l: 1000
            }
        }
    }

    enum Measure: Int, Comparable, Hashable, Sendable {
        case mass, volume, portions

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Ingredient: Hashable, Sendable {
        let name: String
        let amount: Double
        let unit: Unit
    }

    /// A summed quantity in its measure's base unit.
    struct Amount: Hashable, Sendable {
        let measure: Measure
        let value: Double

        var text: String {
            switch measure {
            case .mass:
                value >= 1000 ? "\(decimal(value / 1000)) kg" : "\(Int(value.rounded())) g"
            case .volume:
                value >= 1000 ? "\(decimal(value / 1000)) l" : "\(Int(value.rounded())) ml"
            case .portions:
                String(localized: "\(decimal(value)) × usual portion")
            }
        }

        private func decimal(_ number: Double) -> String {
            number.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    struct Item: Hashable, Identifiable, Sendable {
        /// Normalised name — merges duplicates and keys the checked state.
        let key: String
        let name: String
        /// One per measure, mass first, so "200 g + 1 portion" survives
        /// a merge of rows whose units can't be summed.
        let amounts: [Amount]
        let section: Section

        var id: String { key }
        var quantityText: String { amounts.map(\.text).joined(separator: " + ") }
    }

    struct Group: Hashable, Identifiable, Sendable {
        let section: Section
        let items: [Item]

        var id: Section { section }
    }

    // MARK: - From the meal plan

    /// Every ingredient of `plan` for `days` days. A meal with an
    /// ingredient snapshot contributes its components in grams; one
    /// without uses its serving label when that is a plain amount
    /// ("150 g", "2 dl"), else counts portions of the food itself.
    static func ingredients(from plan: MealPlanEngine.Plan, days: Int) -> [Ingredient] {
        let scale = Double(max(1, days))
        return plan.meals.flatMap { meal -> [Ingredient] in
            let factor = meal.portion * scale
            if let components = meal.food.components, !components.isEmpty {
                return components.map { Ingredient(name: $0.name, amount: $0.grams * factor, unit: .g) }
            }
            if let serving = meal.food.servingLabel.flatMap(parseQuantity) {
                return [Ingredient(name: meal.food.name, amount: serving.amount * factor, unit: serving.unit)]
            }
            return [Ingredient(name: meal.food.name, amount: factor, unit: .portion)]
        }
    }

    /// "150 g", "1,5 l", "2 dl" → amount and unit; nil for anything else
    /// ("1 cup", "1 bar").
    static func parseQuantity(_ label: String) -> (amount: Double, unit: Unit)? {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: ",", with: ".")
        guard let match = text.wholeMatch(of: #/(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|dl|l)/#),
              let amount = Double(match.1), amount > 0,
              let unit = Unit(rawValue: String(match.2)) else { return nil }
        return (amount, unit)
    }

    // MARK: - Merging

    /// Lowercased, trimmed, inner whitespace collapsed to one space.
    static func normalizedName(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Merges ingredients by normalised name, summing amounts that share
    /// a measure. Blank names and non-positive amounts are dropped.
    static func items(from ingredients: [Ingredient]) -> [Item] {
        var order: [String] = []
        var names: [String: String] = [:]
        var totals: [String: [Measure: Double]] = [:]
        for ingredient in ingredients {
            let key = normalizedName(ingredient.name)
            let value = ingredient.amount * ingredient.unit.toBase
            guard !key.isEmpty, value.isFinite, value > 0 else { continue }
            if names[key] == nil {
                order.append(key)
                names[key] = ingredient.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            totals[key, default: [:]][ingredient.unit.measure, default: 0] += value
        }
        return order.map { key in
            let amounts = (totals[key] ?? [:])
                .sorted { $0.key < $1.key }
                .map { Amount(measure: $0.key, value: $0.value) }
            return Item(key: key, name: names[key] ?? key, amounts: amounts, section: section(for: key))
        }
    }

    /// Items grouped by section in store-walk order, each section sorted
    /// by name. Empty sections are left out.
    static func groups(_ items: [Item]) -> [Group] {
        Section.allCases.compactMap { section in
            let members = items
                .filter { $0.section == section }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return members.isEmpty ? nil : Group(section: section, items: members)
        }
    }

    /// Unchecked items first, then checked ones, each half keeping its
    /// order — checking an item sinks it to the bottom of its section.
    static func arranged(_ items: [Item], checked: Set<String>) -> [Item] {
        items.filter { !checked.contains($0.key) } + items.filter { checked.contains($0.key) }
    }

    /// The list as plain text for sharing: what's still left to buy.
    static func plainText(_ groups: [Group], checked: Set<String>) -> String {
        var lines = [String(localized: "Shopping list")]
        for group in groups {
            let remaining = group.items.filter { !checked.contains($0.key) }
            guard !remaining.isEmpty else { continue }
            lines.append("")
            lines.append(group.section.title)
            lines += remaining.map { "• \($0.name) – \($0.quantityText)" }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    /// The section whose longest keyword matches the name; anything
    /// marked frozen goes to Frozen first. A single-word keyword matches
    /// the start or end of any word, so Swedish compounds land too
    /// ("kycklingfilé", "fetaost"); a multi-word one matches as a phrase.
    static func section(for name: String) -> Section {
        let key = normalizedName(name)
        let words = key.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if keywords[.frozen, default: []].contains(where: { matches($0, name: key, words: words) }) {
            return .frozen
        }
        var best: (section: Section, length: Int)?
        for section in [Section.produce, .dairy, .meatFish, .pantry] {
            for keyword in keywords[section, default: []]
            where keyword.count > (best?.length ?? 0) && matches(keyword, name: key, words: words) {
                best = (section, keyword.count)
            }
        }
        return best?.section ?? .other
    }

    private static func matches(_ keyword: String, name: String, words: [String]) -> Bool {
        if keyword.contains(" ") { return name.contains(keyword) }
        return words.contains { $0.hasPrefix(keyword) || $0.hasSuffix(keyword) }
    }

    private static let keywords: [Section: [String]] = [
        .frozen: ["fryst", "frysta", "djupfryst", "frozen", "glass", "ice cream"],
        .produce: [
            "frukt", "fruit", "grönsak", "vegetable", "banan", "banana", "äpple", "apple", "päron", "pear",
            "apelsin", "orange", "citron", "lemon", "lime", "bär", "berry", "berries", "jordgubb", "hallon",
            "druv", "grape", "melon", "mango", "ananas", "pineapple", "kiwi", "avokado", "avocado", "persika",
            "peach", "plommon", "plum", "tomat", "tomato", "gurk", "cucumber", "sallad", "salad", "lettuce",
            "spenat", "spinach", "ruccola", "rocket", "broccoli", "kål", "cabbage", "cauliflower", "morot",
            "morötter", "carrot", "lök", "onion", "garlic", "leek", "potatis", "potato", "sweet potato",
            "paprika", "bell pepper", "zucchini", "squash", "svamp", "champinjon", "mushroom", "ingefära",
            "ginger", "persilja", "parsley", "basilika", "basil", "koriander", "cilantro", "dill", "majs",
            "corn", "ärt", "peas", "sparris", "asparagus", "rödbet", "beetroot", "selleri", "celery",
            "aubergine", "eggplant", "edamame",
        ],
        .dairy: [
            "mjölk", "milk", "filmjölk", "fil", "yoghurt", "yogurt", "kvarg", "quark", "keso", "kesella",
            "cottage", "skyr", "ost", "cheese", "mozzarella", "parmesan", "feta", "halloumi", "smör", "butter",
            "grädde", "cream", "gräddfil", "crème fraiche", "creme fraiche", "ägg", "egg",
        ],
        .meatFish: [
            "kött", "meat", "nötkött", "beef", "färs", "mince", "fläsk", "pork", "skinka", "ham", "bacon",
            "korv", "sausage", "kyckling", "chicken", "kalkon", "turkey", "lamm", "lamb", "biff", "steak",
            "entrecote", "filé", "filet", "fillet", "fisk", "fish", "lax", "salmon", "torsk", "cod", "tonfisk", "tuna",
            "sej", "makrill", "mackerel", "sill", "herring", "räk", "shrimp", "prawn",
        ],
        .pantry: [
            "havregryn", "gryn", "oats", "oat", "müsli", "muesli", "granola", "flingor", "cereal",
            "cornflakes", "ris", "rice", "pasta", "spaghetti", "nudl", "noodle", "mjöl", "flour", "bröd",
            "bread", "knäcke", "tortilla", "wrap", "socker", "sugar", "salt", "olja", "oil", "vinäger",
            "vinegar", "honung", "honey", "sylt", "jam", "sirap", "syrup", "nöt", "nuts", "mandel", "almond",
            "cashew", "jordnöt", "peanut", "peanut butter", "frö", "seed", "chia", "quinoa", "bulgur",
            "couscous", "linser", "lentil", "bönor", "beans", "kikärt", "chickpea", "konserv", "canned",
            "krossade tomater", "passata", "tomatpuré", "buljong", "stock", "krydd", "spice", "kaffe",
            "coffee", "tea", "whey", "proteinpulver", "protein powder", "proteinbar", "protein bar",
            "choklad", "chocolate", "kakao", "cocoa", "kokosmjölk", "coconut milk", "sås", "sauce",
            "ketchup", "senap", "mustard", "majonnäs", "mayo", "soja", "soy",
        ],
    ]
}
