import Foundation

/// Weekly meal prep: which two boxes to cook this week, what to buy, the
/// order to cook it in on prep day and how long each box keeps.
///
/// Pure and deterministic like `RecipeLibraryEngine`, whose ranking it
/// reuses: the clock, the calendar, the pantry and earlier weeks are all
/// passed in. Ties break on the recipe id.
enum WeeklyPrepEngine {

    static let dishesPerWeek = 2
    static let servingRange = 1...12

    // MARK: - Weeks

    /// `calendar` with ISO 8601 week rules (weeks start on Monday, week 1
    /// holds the first Thursday), keeping its time zone and locale.
    static func isoCalendar(_ calendar: Calendar) -> Calendar {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        return iso
    }

    /// Monday 00:00 of the ISO week holding `date`.
    static func weekStart(for date: Date, calendar: Calendar) -> Date {
        let iso = isoCalendar(calendar)
        return iso.dateInterval(of: .weekOfYear, for: date)?.start ?? iso.startOfDay(for: date)
    }

    static func weekNumber(for date: Date, calendar: Calendar) -> Int {
        isoCalendar(calendar).component(.weekOfYear, from: date)
    }

    /// The plan for the week holding `now`, or an empty one when the week
    /// has none yet, so a new week starts clean.
    static func plan(for now: Date, in plans: [PrepWeek], calendar: Calendar) -> PrepWeek {
        let start = weekStart(for: now, calendar: calendar)
        return plans.first { $0.weekStart == start } ?? PrepWeek(weekStart: start)
    }

    static let varietyWeeks = 2
    static let keptWeeks = 8

    /// Recipes planned in the `varietyWeeks` weeks before the one holding `now`.
    static func recentRecipeIDs(in plans: [PrepWeek], before now: Date, calendar: Calendar) -> Set<String> {
        let start = weekStart(for: now, calendar: calendar)
        guard let earliest = calendar.date(byAdding: .day, value: -7 * varietyWeeks, to: start) else { return [] }
        return Set(plans.filter { $0.weekStart >= earliest && $0.weekStart < start }.flatMap(\.recipeIDs))
    }

    /// Drops plans older than `keptWeeks`: they only ever feed variety.
    static func pruned(_ plans: [PrepWeek], now: Date, calendar: Calendar) -> [PrepWeek] {
        let start = weekStart(for: now, calendar: calendar)
        guard let earliest = calendar.date(byAdding: .day, value: -7 * keptWeeks, to: start) else { return plans }
        return plans.filter { $0.weekStart >= earliest }
    }

    // MARK: - Suggestion

    /// Where a dish's protein comes from, so a week doesn't get two
    /// chicken boxes.
    enum ProteinSource: String, Sendable {
        case chicken, turkey, beef, pork, lamb, fish, legumes, soy, egg, cheese
    }

    private static let proteinSources: [String: ProteinSource] = [
        "chicken breast": .chicken, "chicken thigh": .chicken,
        "turkey mince": .turkey, "turkey breast": .turkey,
        "minced beef": .beef, "beef chuck": .beef, "beef": .beef,
        "pork tenderloin": .pork, "ham": .pork,
        "lamb mince": .lamb,
        "salmon": .fish, "cod": .fish, "pollock": .fish, "tuna": .fish, "shrimp": .fish,
        "smoked salmon": .fish, "sardine": .fish, "mackerel in tomato sauce": .fish, "pickled herring": .fish,
        "black bean": .legumes, "chickpea": .legumes, "green lentil": .legumes, "lentil": .legumes,
        "white bean": .legumes, "kidney bean": .legumes, "yellow pea": .legumes,
        "tofu": .soy, "tempeh": .soy, "soy mince": .soy, "edamame": .soy,
        "egg": .egg,
        "halloumi": .cheese, "cottage cheese": .cheese, "quark": .cheese,
    ]

    /// The first protein in the ingredient list; recipes list their main
    /// ingredient first.
    static func mainProtein(of recipe: LibraryRecipe) -> ProteinSource? {
        recipe.ingredients.lazy.compactMap { proteinSources[$0.pantryKey] }.first
    }

    /// Lunch and dinner boxes. Breakfast prep (overnight oats) isn't one
    /// of the week's two main dishes.
    static func candidates(_ recipes: [LibraryRecipe]) -> [LibraryRecipe] {
        recipes.filter { $0.mealPrep && ($0.category == .lunch || $0.category == .dinner) }
    }

    /// A box planned in the last two weeks scores this much lower.
    static let repeatPenalty = 30.0

    /// Meal-prep recipes, best first: the library's ranking (favourites,
    /// protein density, the pantry, meals eaten lately) without its
    /// time-of-day nudge — a box gets eaten at any meal — and lower for
    /// boxes planned in the last two weeks.
    static func ranked(
        _ recipes: [LibraryRecipe],
        context: RecipeLibraryEngine.Context,
        recentRecipeIDs: Set<String>
    ) -> [LibraryRecipe] {
        let slot = MealCategory.auto(for: context.now, calendar: context.calendar)
        return candidates(recipes)
            .map { recipe -> (recipe: LibraryRecipe, score: Double) in
                var score = RecipeLibraryEngine.recommendation(for: recipe, context: context).score
                if recipe.category == slot { score -= RecipeLibraryEngine.timeOfDayBonus }
                if recentRecipeIDs.contains(recipe.id) { score -= repeatPenalty }
                return (recipe, score)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.recipe.id < $1.recipe.id }
            .map { $0.recipe }
    }

    /// The week's two boxes: the best-ranked recipe, then the best one
    /// built on a different protein. Each at the servings it is written for.
    static func suggestWeek(from ranked: [LibraryRecipe]) -> [PrepDish] {
        var picked: [LibraryRecipe] = []
        for recipe in ranked where picked.count < dishesPerWeek {
            let protein = mainProtein(of: recipe)
            let clashes = picked.contains { protein != nil && mainProtein(of: $0) == protein }
            if !clashes { picked.append(recipe) }
        }
        // A library too small to vary still fills the week.
        for recipe in ranked where picked.count < dishesPerWeek && !picked.contains(recipe) {
            picked.append(recipe)
        }
        return picked.map { PrepDish(recipeID: $0.id, servings: $0.servings) }
    }

    // MARK: - Shopping list

    /// Store sections in the order a shop is usually walked.
    enum ShoppingSection: Int, CaseIterable, Identifiable, Sendable {
        case produce, meatAndFish, dairy, frozen, pantry

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .produce:     String(localized: "Fruit & veg", comment: "Shopping list section")
            case .meatAndFish: String(localized: "Meat & fish", comment: "Shopping list section")
            case .dairy:       String(localized: "Dairy & chilled", comment: "Shopping list section")
            case .frozen:      String(localized: "Frozen", comment: "Shopping list section")
            case .pantry:      String(localized: "Pantry", comment: "Shopping list section: dry goods, tins and spices")
            }
        }

        var icon: String {
            switch self {
            case .produce:     "carrot.fill"
            case .meatAndFish: "fish.fill"
            case .dairy:       "drop.fill"
            case .frozen:      "snowflake"
            case .pantry:      "cabinet.fill"
            }
        }
    }

    private static let sectionKeys: [ShoppingSection: Set<String>] = [
        .produce: [
            "apple", "asparagus", "avocado", "banana", "beetroot", "bell pepper", "blueberry", "broccoli",
            "butternut squash", "cabbage", "carrot", "cauliflower", "cucumber", "eggplant", "garlic", "ginger",
            "green bean", "kale", "leek", "lemon", "lettuce", "lime", "mango", "mushroom", "onion", "orange",
            "parsnip", "pear", "potato", "raspberry", "spinach", "strawberry", "sugar snap pea", "sweet potato",
            "tomato", "zucchini",
        ],
        .meatAndFish: [
            "beef", "beef chuck", "chicken breast", "chicken thigh", "cod", "ham", "lamb mince", "minced beef",
            "pollock", "pork tenderloin", "salmon", "shrimp", "smoked salmon", "turkey breast", "turkey mince",
        ],
        .dairy: [
            "cheese", "cottage cheese", "creme fraiche", "egg", "feta", "halloumi", "milk", "oat drink", "parmesan",
            "quark", "skyr", "soy yogurt", "yogurt", "tofu", "tempeh", "soy mince", "hummus", "pesto",
            "pickled herring",
        ],
        .frozen: ["frozen berries", "green pea", "edamame"],
    ]

    static func section(for pantryKey: String) -> ShoppingSection {
        sectionKeys.first { $0.value.contains(pantryKey) }?.key ?? .pantry
    }

    struct ShoppingItem: Hashable, Identifiable, Sendable {
        let pantryKey: String
        let name: String
        let nameSV: String
        /// The whole week's amount.
        let grams: Double
        let section: ShoppingSection
        let isAtHome: Bool

        var id: String { pantryKey }

        func displayName(locale: Locale) -> String {
            LibraryRecipe.isSwedish(locale) ? nameSV : name
        }
    }

    struct ShoppingGroup: Hashable, Identifiable, Sendable {
        let section: ShoppingSection
        let items: [ShoppingItem]
        var id: Int { section.id }
    }

    /// Every ingredient of the week once: grams summed across the dishes at
    /// their servings, merged on the pantry key and marked when it is
    /// already at home. In recipe order, the week's first dish first.
    static func shoppingList(
        for dishes: [PrepDish],
        recipes: [String: LibraryRecipe],
        pantry: Set<String>
    ) -> [ShoppingItem] {
        var order: [String] = []
        var first: [String: LibraryRecipe.Ingredient] = [:]
        var grams: [String: Double] = [:]
        for dish in dishes {
            guard let recipe = recipes[dish.recipeID] else { continue }
            for ingredient in recipe.ingredients {
                let key = ingredient.pantryKey
                if first[key] == nil {
                    first[key] = ingredient
                    order.append(key)
                }
                grams[key, default: 0] += RecipeLibraryEngine.grams(ingredient, servings: dish.servings)
            }
        }
        return order.compactMap { key -> ShoppingItem? in
            guard let ingredient = first[key] else { return nil }
            return ShoppingItem(
                pantryKey: key,
                name: ingredient.name,
                nameSV: ingredient.nameSV,
                grams: grams[key] ?? 0,
                section: section(for: key),
                isAtHome: pantry.contains(key)
            )
        }
    }

    /// The list by store section; within a section what is still to buy
    /// comes before what is at home.
    static func grouped(_ items: [ShoppingItem]) -> [ShoppingGroup] {
        ShoppingSection.allCases.compactMap { section -> ShoppingGroup? in
            let inSection = items.filter { $0.section == section }
            guard !inSection.isEmpty else { return nil }
            return ShoppingGroup(
                section: section,
                items: inSection.filter { !$0.isAtHome } + inSection.filter(\.isAtHome)
            )
        }
    }

    // MARK: - Prep day

    struct PrepTask: Hashable, Identifiable, Sendable {
        enum Phase: Int, CaseIterable, Sendable {
            /// What takes longest: the oven, the pot of rice, the stew.
            case start
            case cook
            case pack
        }

        enum Kind: Hashable, Sendable {
            /// The recipe's own step at this index.
            case step(Int)
            /// Divide the dish into this many boxes.
            case portion(boxes: Int)
            /// Cool everything before the lids go on.
            case cool
        }

        let recipeID: String?
        let kind: Kind
        let phase: Phase

        var id: String {
            switch kind {
            case .step(let index): "\(recipeID ?? "")#step\(index)"
            case .portion:         "\(recipeID ?? "")#portion"
            case .cool:            "cool"
            }
        }
    }

    private static let longCookWords = [
        "simmer", "bake", "roast", "boil", "oven", "°c", "hour",
        "cook the rice", "cook the quinoa", "cook the bulgur", "cook the pasta", "cook the barley",
    ]
    private static let packWords = ["box", "pack", "divide"]

    /// A step that needs the oven or a pot on for a while.
    static func isLongCook(_ step: String) -> Bool {
        let text = step.lowercased()
        return longCookWords.contains { text.contains($0) }
    }

    static func isPackStep(_ step: String) -> Bool {
        let text = step.lowercased()
        return packWords.contains { text.contains($0) }
    }

    /// Prep day in order. The longest recipe goes first. A recipe that
    /// opens with something slow (rice, the oven, a stew) gets that step
    /// started before anything else; the rest of each recipe follows in its
    /// own order, and packing comes last, then cooling.
    ///
    /// Steps are matched in English, which every recipe carries; the view
    /// shows them in the user's language by index.
    static func prepTasks(for dishes: [PrepDish], recipes: [String: LibraryRecipe]) -> [PrepTask] {
        let planned = dishes
            .compactMap { dish in recipes[dish.recipeID].map { (recipe: $0, servings: dish.servings) } }
            .sorted { $0.recipe.minutes != $1.recipe.minutes ? $0.recipe.minutes > $1.recipe.minutes : $0.recipe.id < $1.recipe.id }
        guard !planned.isEmpty else { return [] }

        var start: [PrepTask] = []
        var cook: [PrepTask] = []
        var pack: [PrepTask] = []
        for (recipe, servings) in planned {
            var indices = Array(recipe.steps.indices)
            let packIndex = indices.last.flatMap { isPackStep(recipe.steps[$0]) ? $0 : nil }
            if packIndex != nil { indices.removeLast() }
            if let first = indices.first, isLongCook(recipe.steps[first]) {
                start.append(PrepTask(recipeID: recipe.id, kind: .step(first), phase: .start))
                indices.removeFirst()
            }
            cook += indices.map { PrepTask(recipeID: recipe.id, kind: .step($0), phase: .cook) }
            if let packIndex {
                pack.append(PrepTask(recipeID: recipe.id, kind: .step(packIndex), phase: .pack))
            }
            pack.append(PrepTask(recipeID: recipe.id, kind: .portion(boxes: servings), phase: .pack))
        }
        pack.append(PrepTask(recipeID: nil, kind: .cool, phase: .pack))
        return start + cook + pack
    }

    // MARK: - Boxes

    /// Months a box keeps in the freezer.
    static let freezerMonths = 3
    /// For a recipe that doesn't say how long it keeps.
    static let defaultFridgeDays = 3

    /// The boxes prep day makes: one batch per dish, a box per serving.
    static func boxes(for dishes: [PrepDish], cookedAt: Date) -> [PrepBoxBatch] {
        dishes.filter { $0.servings > 0 }.map {
            PrepBoxBatch(id: UUID(), recipeID: $0.recipeID, cookedAt: cookedAt, frozenAt: nil, count: $0.servings)
        }
    }

    /// Start of the last day the batch should be eaten: cooked day plus the
    /// recipe's fridge days, or three months from the day it was frozen.
    static func eatBy(_ batch: PrepBoxBatch, fridgeDays: Int?, calendar: Calendar) -> Date {
        if let frozenAt = batch.frozenAt {
            let day = calendar.startOfDay(for: frozenAt)
            return calendar.date(byAdding: .month, value: freezerMonths, to: day) ?? day
        }
        let day = calendar.startOfDay(for: batch.cookedAt)
        return calendar.date(byAdding: .day, value: fridgeDays ?? defaultFridgeDays, to: day) ?? day
    }

    enum Freshness: Hashable, Sendable {
        case fresh
        /// Eat today or tomorrow.
        case soon
        case expired
    }

    static func freshness(eatBy: Date, now: Date, calendar: Calendar) -> Freshness {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: eatBy).day ?? 0
        if days < 0 { return .expired }
        return days <= 1 ? .soon : .fresh
    }

    /// One box fewer; the batch goes when it is empty.
    static func removingOne(from batches: [PrepBoxBatch], id: UUID) -> [PrepBoxBatch] {
        batches.compactMap { batch -> PrepBoxBatch? in
            guard batch.id == id else { return batch }
            guard batch.count > 1 else { return nil }
            var rest = batch
            rest.count -= 1
            return rest
        }
    }

    /// Moves one box of a fridge batch into the freezer, joining the frozen
    /// boxes from the same cook when there are any.
    static func freezingOne(from batches: [PrepBoxBatch], id: UUID, at now: Date) -> [PrepBoxBatch] {
        guard let batch = batches.first(where: { $0.id == id }), !batch.isFrozen else { return batches }
        var result = removingOne(from: batches, id: id)
        if let index = result.firstIndex(where: {
            $0.isFrozen && $0.recipeID == batch.recipeID && $0.cookedAt == batch.cookedAt
        }) {
            result[index].count += 1
        } else {
            result.append(PrepBoxBatch(id: UUID(), recipeID: batch.recipeID, cookedAt: batch.cookedAt, frozenAt: now, count: 1))
        }
        return result
    }

    /// Fridge boxes before frozen ones, each soonest-to-expire first.
    static func sorted(
        _ batches: [PrepBoxBatch],
        recipes: [String: LibraryRecipe],
        calendar: Calendar
    ) -> [PrepBoxBatch] {
        batches.sorted { lhs, rhs in
            if lhs.isFrozen != rhs.isFrozen { return !lhs.isFrozen }
            let left = eatBy(lhs, fridgeDays: recipes[lhs.recipeID]?.fridgeDays, calendar: calendar)
            let right = eatBy(rhs, fridgeDays: recipes[rhs.recipeID]?.fridgeDays, calendar: calendar)
            return left != right ? left < right : lhs.recipeID < rhs.recipeID
        }
    }

    /// Days past eat-by an expired batch stays on screen to be thrown out.
    static let expiredGraceDays = 7

    static func pruned(
        _ batches: [PrepBoxBatch],
        recipes: [String: LibraryRecipe],
        now: Date,
        calendar: Calendar
    ) -> [PrepBoxBatch] {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -expiredGraceDays, to: today) else { return batches }
        return batches.filter {
            $0.count >= 1 && eatBy($0, fridgeDays: recipes[$0.recipeID]?.fridgeDays, calendar: calendar) >= cutoff
        }
    }

    // MARK: - Reminder

    static let reminderHour = 18

    /// The evening before the soonest fridge eat-by still ahead, with the
    /// batches due that day. Frozen boxes don't need one.
    static func nextReminder(
        for batches: [PrepBoxBatch],
        recipes: [String: LibraryRecipe],
        now: Date,
        calendar: Calendar
    ) -> (fireDate: Date, recipeIDs: [String])? {
        let due = Dictionary(grouping: batches.filter { !$0.isFrozen }) {
            eatBy($0, fridgeDays: recipes[$0.recipeID]?.fridgeDays, calendar: calendar)
        }
        for day in due.keys.sorted() {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: day),
                  let fireDate = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: dayBefore),
                  fireDate > now
            else { continue }
            var seen: Set<String> = []
            let ids = (due[day] ?? []).map(\.recipeID).sorted().filter { seen.insert($0).inserted }
            return (fireDate, ids)
        }
        return nil
    }
}
