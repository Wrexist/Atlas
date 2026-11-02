import Foundation

/// The fridge's rules: how fresh each item is, what it counts as in the
/// recipe library, which recipes it can make, and when to remind.
///
/// Pure: the clock, the calendar and the recipes are passed in.
enum FridgeEngine {

    // MARK: - Freshness

    enum Freshness: Equatable, Sendable {
        case expired(daysAgo: Int)
        case today
        case soon(daysLeft: Int)
        case fresh(daysLeft: Int)
        case unknown

        /// Expired, today or soon: what the "Use soon" section holds.
        var needsUse: Bool {
            switch self {
            case .expired, .today, .soon: true
            case .fresh, .unknown: false
            }
        }
    }

    /// Days left at or under which an item counts as "use soon".
    static let soonDays = 2

    static func freshness(_ expiresOn: Date?, now: Date, calendar: Calendar) -> Freshness {
        guard let expiresOn else { return .unknown }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiresOn)
        ).day ?? 0
        switch days {
        case ..<0: return .expired(daysAgo: -days)
        case 0: return .today
        case 1...soonDays: return .soon(daysLeft: days)
        default: return .fresh(daysLeft: days)
        }
    }

    /// The use-by day `shelfDays` after `day`, at its start.
    static func expiry(from day: Date, shelfDays: Int?, calendar: Calendar) -> Date? {
        guard let shelfDays else { return nil }
        return calendar.date(byAdding: .day, value: shelfDays, to: calendar.startOfDay(for: day))
    }

    /// A cautious guess for a product with no printed date: fresh meat
    /// and fish keep a few days, dairy about a week, the freezer months.
    /// Cupboard goods and anything unrecognised get no date rather than
    /// an invented one.
    static func defaultShelfDays(place: FridgePlace, pantryKey: String?) -> Int? {
        switch place {
        case .freezer: return 90
        case .pantry: return nil
        case .fridge:
            guard let pantryKey else { return nil }
            switch WeeklyPrepEngine.section(for: pantryKey) {
            case .meatAndFish: return 3
            case .dairy: return 10
            case .produce: return 6
            case .frozen: return 2
            case .pantry: return 21
            }
        }
    }

    // MARK: - Recipe keys

    /// The recipe ingredient a product name counts as, or nil when nothing
    /// fits. A whole word scores highest; a Swedish compound sharing its
    /// head or its start ("mellanmjölk" ~ "mjölk", "vitlök" over "lök")
    /// counts for less.
    static func pantryKey(for name: String, ingredients: [LibraryRecipe.Ingredient]) -> String? {
        let nameWords = RecipeLibraryEngine.words(name)
        guard !nameWords.isEmpty else { return nil }
        var best: (key: String, score: Int)?
        var seen: Set<String> = []
        for ingredient in ingredients where seen.insert(ingredient.pantryKey).inserted {
            let ingredientWords = RecipeLibraryEngine.words("\(ingredient.pantryKey) \(ingredient.name) \(ingredient.nameSV)")
            let score = nameWords.map { word in ingredientWords.map { matchScore(word, $0) }.max() ?? 0 }.reduce(0, +)
            if score > (best?.score ?? 0) { best = (ingredient.pantryKey, score) }
        }
        return best?.key
    }

    private static func matchScore(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs { return 3 }
        let (short, long) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        if long.hasSuffix(short) { return 2 }
        if long.hasPrefix(short) { return 1 }
        return 0
    }

    /// Keys of everything at home and not past its date.
    static func pantryKeys(items: [FridgeItem], products: [UUID: FridgeProduct], now: Date, calendar: Calendar) -> Set<String> {
        Set(items.compactMap { item -> String? in
            if case .expired = freshness(item.expiresOn, now: now, calendar: calendar) { return nil }
            return products[item.productID]?.pantryKey
        })
    }

    /// Keys of what should be eaten within `soonDays`.
    static func expiringKeys(items: [FridgeItem], products: [UUID: FridgeProduct], now: Date, calendar: Calendar) -> Set<String> {
        Set(items.compactMap { item -> String? in
            switch freshness(item.expiresOn, now: now, calendar: calendar) {
            case .today, .soon: products[item.productID]?.pantryKey
            default: nil
            }
        })
    }

    // MARK: - Cooking from the fridge

    struct Suggestion: Identifiable, Hashable, Sendable {
        let recipe: LibraryRecipe
        let have: Int
        let total: Int
        /// Ingredients to buy to complete it, in recipe order.
        let missing: [LibraryRecipe.Ingredient]
        /// It uses something that should be eaten soon.
        let rescuesExpiring: Bool

        var id: String { recipe.id }
    }

    /// Share of a recipe that must already be at home to be suggested,
    /// unless it saves something about to go off.
    static let suggestionThreshold = 0.5

    /// Recipes that cook from the fridge: ones saving food about to go off
    /// first, then the most complete. `fridgeKeys` must contribute, or a
    /// recipe made only of cupboard ticks would be "from your fridge".
    static func suggestions(
        recipes: [LibraryRecipe],
        have: Set<String>,
        fridgeKeys: Set<String>,
        expiringKeys: Set<String>,
        limit: Int = 6
    ) -> [Suggestion] {
        guard !fridgeKeys.isEmpty else { return [] }
        let candidates = recipes.compactMap { recipe -> Suggestion? in
            let keys = recipe.pantryKeys
            guard !keys.isEmpty, keys.contains(where: fridgeKeys.contains) else { return nil }
            let haveCount = keys.filter(have.contains).count
            let rescues = keys.contains(where: expiringKeys.contains)
            guard rescues || Double(haveCount) / Double(keys.count) >= suggestionThreshold else { return nil }
            var seen: Set<String> = []
            let missing = recipe.ingredients.filter { !have.contains($0.pantryKey) && seen.insert($0.pantryKey).inserted }
            return Suggestion(recipe: recipe, have: haveCount, total: keys.count, missing: missing, rescuesExpiring: rescues)
        }
        return Array(candidates.sorted(by: ranksBefore).prefix(limit))
    }

    private static func ranksBefore(_ lhs: Suggestion, _ rhs: Suggestion) -> Bool {
        if lhs.rescuesExpiring != rhs.rescuesExpiring { return lhs.rescuesExpiring }
        if lhs.missing.count != rhs.missing.count { return lhs.missing.count < rhs.missing.count }
        if lhs.have != rhs.have { return lhs.have > rhs.have }
        return lhs.recipe.id < rhs.recipe.id
    }

    // MARK: - Listing

    /// Soonest use-by first; undated items last, by name.
    static func sorted(_ items: [FridgeItem], products: [UUID: FridgeProduct]) -> [FridgeItem] {
        items.sorted { lhs, rhs in
            switch (lhs.expiresOn, rhs.expiresOn) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                let lName = products[lhs.productID]?.name ?? ""
                let rName = products[rhs.productID]?.name ?? ""
                return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
            }
        }
    }

    /// Saved products matching every typed word in name, brand or barcode;
    /// the most recently bought first. An empty query lists them all.
    static func search(_ products: [FridgeProduct], query: String) -> [FridgeProduct] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return products
            .filter { product in
                let haystack = "\(product.name) \(product.brand ?? "") \(product.barcode ?? "")".lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            .sorted { ($0.lastAddedAt ?? .distantPast) > ($1.lastAddedAt ?? .distantPast) }
    }

    // MARK: - Reminders

    /// Hour of the evening-before reminder, and of the morning-of one used
    /// when the evening has already passed.
    static let eveningHour = 18
    static let morningHour = 8

    struct Reminder: Equatable, Sendable {
        let fireDate: Date
        /// The use-by day; the same day as `fireDate` for a morning-of one.
        let useBy: Date
        let itemIDs: [UUID]
    }

    /// The next "use by tomorrow" reminder: the evening before the soonest
    /// use-by day still ahead, or that morning when the evening is gone.
    /// Covers every item due that day.
    static func nextReminder(for items: [FridgeItem], now: Date, calendar: Calendar) -> Reminder? {
        let due = Dictionary(grouping: items.filter { $0.expiresOn != nil }) {
            calendar.startOfDay(for: $0.expiresOn ?? now)
        }
        for day in due.keys.sorted() {
            guard let fireDate = fireDate(for: day, now: now, calendar: calendar) else { continue }
            return Reminder(fireDate: fireDate, useBy: day, itemIDs: (due[day] ?? []).map(\.id))
        }
        return nil
    }

    private static func fireDate(for day: Date, now: Date, calendar: Calendar) -> Date? {
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: day),
           let evening = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: dayBefore),
           evening > now {
            return evening
        }
        if let morning = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: day), morning > now {
            return morning
        }
        return nil
    }
}
