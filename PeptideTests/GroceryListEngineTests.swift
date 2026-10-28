import XCTest
@testable import Peptide

final class GroceryListEngineTests: XCTestCase {

    private typealias Engine = GroceryListEngine

    private func ingredient(_ name: String, _ amount: Double, _ unit: Engine.Unit) -> Engine.Ingredient {
        Engine.Ingredient(name: name, amount: amount, unit: unit)
    }

    private func food(
        _ name: String,
        components: [MealFoodComponent]? = nil,
        servingLabel: String? = nil
    ) -> MealPlanEngine.Food {
        MealPlanEngine.Food(
            id: "custom:\(name)",
            name: name,
            calories: 300,
            proteinG: 20,
            carbsG: 0,
            fatG: 0,
            slots: [],
            source: .custom,
            sourceID: "custom:\(name)",
            components: components,
            servingLabel: servingLabel
        )
    }

    private func component(_ name: String, grams: Double) -> MealFoodComponent {
        MealFoodComponent(
            id: name,
            name: name,
            grams: grams,
            servingGrams: nil,
            servingLabel: nil,
            per100g: .zero,
            sourceID: nil
        )
    }

    private func plan(_ meals: [MealPlanEngine.PlannedMeal]) -> MealPlanEngine.Plan {
        MealPlanEngine.Plan(meals: meals, targetCalories: 2000, targetProteinG: 150)
    }

    // MARK: - Merging

    func test_sameNameDifferentCaseAndSpacing_mergesIntoOneItem() {
        let items = Engine.items(from: [
            ingredient("Chicken  breast", 200, .g),
            ingredient(" chicken breast ", 150, .g),
            ingredient("CHICKEN BREAST", 50, .g),
        ])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.key, "chicken breast")
        XCTAssertEqual(items.first?.name, "Chicken breast")
        XCTAssertEqual(items.first?.amounts, [Engine.Amount(measure: .mass, value: 400)])
    }

    func test_kilogramsAndGrams_sumInGrams() {
        let items = Engine.items(from: [ingredient("Ris", 1.2, .kg), ingredient("ris", 300, .g)])

        XCTAssertEqual(items.first?.amounts, [Engine.Amount(measure: .mass, value: 1500)])
        XCTAssertEqual(items.first?.amounts.first?.text.hasSuffix("kg"), true)
    }

    func test_litresDecilitresAndMillilitres_sumInMillilitres() {
        let items = Engine.items(from: [
            ingredient("Mjölk", 1, .l),
            ingredient("mjölk", 2, .dl),
            ingredient("mjölk", 50, .ml),
        ])

        XCTAssertEqual(items.first?.amounts, [Engine.Amount(measure: .volume, value: 1250)])
    }

    func test_unitsThatCannotBeSummed_keepOneAmountPerMeasure() {
        let items = Engine.items(from: [
            ingredient("Yoghurt", 1, .portion),
            ingredient("yoghurt", 200, .g),
            ingredient("yoghurt", 1, .dl),
        ])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.amounts.map(\.measure), [.mass, .volume, .portions])
    }

    func test_blankNamesAndNonPositiveAmounts_areDropped() {
        let items = Engine.items(from: [
            ingredient("   ", 100, .g),
            ingredient("Banan", 0, .g),
            ingredient("Äpple", -5, .g),
            ingredient("Lax", .nan, .g),
        ])

        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Sections

    func test_swedishAndEnglishNames_landInTheirStoreSections() {
        let expected: [String: Engine.Section] = [
            "Banan": .produce,
            "Cherry tomatoes": .produce,
            "Rödlök": .produce,
            "Mellanmjölk 1,5%": .dairy,
            "Fetaost": .dairy,
            "Greek yogurt": .dairy,
            "Ägg": .dairy,
            "Kycklingfilé": .meatFish,
            "Salmon fillet": .meatFish,
            "Havregryn": .pantry,
            "Jasminris": .pantry,
            "Fullkornspasta": .pantry,
            "Frysta blåbär": .frozen,
            "Frozen peas": .frozen,
            "Vitaminer": .other,
        ]
        for (name, section) in expected {
            XCTAssertEqual(Engine.section(for: name), section, name)
        }
    }

    func test_longerKeyword_beatsShorterOneFromAnotherSection() {
        XCTAssertEqual(Engine.section(for: "Peanut butter"), .pantry)
        XCTAssertEqual(Engine.section(for: "Jordnötssmör"), .pantry)
        XCTAssertEqual(Engine.section(for: "Kokosmjölk"), .pantry)
        XCTAssertEqual(Engine.section(for: "Nötkött"), .meatFish)
        XCTAssertEqual(Engine.section(for: "Eggplant"), .produce)
    }

    func test_groups_followStoreOrderAndSkipEmptySections() {
        let items = Engine.items(from: [
            ingredient("Lax", 300, .g),
            ingredient("Banan", 240, .g),
            ingredient("Äpple", 150, .g),
        ])

        let groups = Engine.groups(items)

        XCTAssertEqual(groups.map(\.section), [.produce, .meatFish])
        XCTAssertEqual(groups.first?.items.map(\.name), ["Äpple", "Banan"].sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        })
    }

    // MARK: - Checked state

    func test_checkedItems_sinkBelowUncheckedOnesKeepingOrder() {
        let items = Engine.items(from: ["A", "B", "C", "D"].map { ingredient($0, 1, .portion) })

        let arranged = Engine.arranged(items, checked: ["a", "c"])

        XCTAssertEqual(arranged.map(\.key), ["b", "d", "a", "c"])
    }

    func test_plainText_listsOnlyWhatIsLeftToBuyBySection() {
        let groups = Engine.groups(Engine.items(from: [
            ingredient("Banan", 240, .g),
            ingredient("Lax", 300, .g),
            ingredient("Havregryn", 80, .g),
        ]))

        let text = Engine.plainText(groups, checked: ["havregryn"])

        XCTAssertTrue(text.contains("Banan"))
        XCTAssertTrue(text.contains("Lax"))
        XCTAssertFalse(text.contains("Havregryn"))
        XCTAssertFalse(text.contains(Engine.Section.pantry.title))
    }

    // MARK: - From the meal plan

    func test_planWithComponents_scalesGramsByPortionAndDays() {
        let breakfast = MealPlanEngine.PlannedMeal(
            slot: .breakfast,
            food: food("Gröt", components: [component("Havregryn", grams: 60), component("Mjölk", grams: 200)]),
            portion: 1.5
        )
        let snack = MealPlanEngine.PlannedMeal(
            slot: .snack,
            food: food("Havregryn", components: [component("havregryn", grams: 40)]),
            portion: 1
        )

        let items = Engine.items(from: Engine.ingredients(from: plan([breakfast, snack]), days: 7))

        let oats = items.first { $0.key == "havregryn" }
        XCTAssertEqual(oats?.amounts, [Engine.Amount(measure: .mass, value: (60 * 1.5 + 40) * 7)])
        XCTAssertEqual(items.first { $0.key == "mjölk" }?.amounts.first?.value, 200 * 1.5 * 7)
    }

    func test_planWithoutComponents_usesServingLabelOrCountsPortions() {
        let juice = MealPlanEngine.PlannedMeal(slot: .breakfast, food: food("Juice", servingLabel: "2 dl"), portion: 1)
        let bar = MealPlanEngine.PlannedMeal(slot: .snack, food: food("Proteinbar", servingLabel: "1 bar"), portion: 2)

        let items = Engine.items(from: Engine.ingredients(from: plan([juice, bar]), days: 3))

        XCTAssertEqual(items.first { $0.key == "juice" }?.amounts, [Engine.Amount(measure: .volume, value: 600)])
        XCTAssertEqual(items.first { $0.key == "proteinbar" }?.amounts, [Engine.Amount(measure: .portions, value: 6)])
    }

    func test_parseQuantity_readsPlainAmountsOnly() {
        XCTAssertEqual(Engine.parseQuantity("150 g")?.amount, 150)
        XCTAssertEqual(Engine.parseQuantity("1,5 l")?.unit, .l)
        XCTAssertEqual(Engine.parseQuantity(" 2DL ")?.amount, 2)
        XCTAssertNil(Engine.parseQuantity("1 cup"))
        XCTAssertNil(Engine.parseQuantity("0 g"))
    }
}

@MainActor
final class GroceryChecklistStoreTests: XCTestCase {

    private func makeStore() -> GroceryChecklistStore {
        let suite = "GroceryChecklistStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return GroceryChecklistStore(defaults: defaults)
    }

    func test_clearChecked_movesCheckedRowsToCleared() {
        let store = makeStore()
        store.toggle("banan")
        store.toggle("lax")
        store.toggle("lax")

        store.clearChecked()

        XCTAssertEqual(store.checked, [])
        XCTAssertEqual(store.cleared, ["banan"])
    }

    func test_retain_forgetsRowsNoLongerOnTheList() {
        let store = makeStore()
        store.toggle("banan")
        store.toggle("lax")
        store.clearChecked()
        store.toggle("ris")

        store.retain(["lax", "ris"])

        XCTAssertEqual(store.checked, ["ris"])
        XCTAssertEqual(store.cleared, ["lax"])
    }

    func test_checkedState_persistsAcrossInstances() {
        let suite = "GroceryChecklistStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        GroceryChecklistStore(defaults: defaults).toggle("havregryn")

        XCTAssertEqual(GroceryChecklistStore(defaults: defaults).checked, ["havregryn"])
    }
}
