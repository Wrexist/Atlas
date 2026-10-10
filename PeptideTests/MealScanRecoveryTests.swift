import XCTest
@testable import Peptide

@MainActor
final class MealScanRecoveryTests: XCTestCase {
    private func food() -> EditableFoodItem {
        EditableFoodItem(from: .init(name: "Oats", quantityLabel: "1 bowl", grams: 200,
                                    calories: 200, proteinG: 10, carbsG: 30, fatG: 4, confidence: 0.8))
    }
    private func draft() -> MealScanDraft {
        MealScanDraft(items: [food()], photo: Data([1, 2, 3]), date: Date(timeIntervalSince1970: 100),
                      category: .breakfast, suggestedName: "Breakfast", name: "My oats", combine: true)
    }
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MealRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testDraftRelaunchPreservesCorrectionsExclusionsDateAndPendingIdentity() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "draft.json")
        var value = draft()
        value.items[0].correctNutrition(.init(calories: 300, proteinG: 20, carbsG: 40, fatG: 7))
        value.items[0].grams = 125.5
        value.items[0].include = false
        value.pendingEntries = [MealEntry(date: value.date, category: .breakfast, name: "Oats",
            calories: 300, proteinG: 20, carbsG: 40, fatG: 7, source: .photo, components: [value.items[0].component])]
        value.undoRequested = true
        try MealScanDraftStore(url: url).save(value)
        let reopened = try XCTUnwrap(MealScanDraftStore(url: url).load())
        XCTAssertEqual(reopened.items, value.items)
        XCTAssertEqual(reopened.photo, value.photo)
        XCTAssertEqual(reopened.date, value.date)
        XCTAssertEqual(reopened.name, value.name)
        XCTAssertEqual(reopened.pendingEntries, value.pendingEntries)
        XCTAssertTrue(reopened.undoRequested)
        try MealScanDraftStore(url: url).discard()
        XCTAssertNil(try MealScanDraftStore(url: url).load())
    }

    func testCorruptDraftIsNotSilentlyRemovedAndWriteFailureThrows() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "draft.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try MealScanDraftStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        let blocked = url.appending(path: "cannot-create-child.json")
        XCTAssertThrowsError(try MealScanDraftStore(url: blocked).save(draft()))
    }

    func testDurableRetryRelaunchAndUndoDoNotDuplicateMeals() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "meals.store")
        let repo = SwiftDataRepository.shared
        try repo.configurePersistentStoreForTesting(at: url)
        defer {
            repo.forceCommitFailureForTesting = false
            DataStore.current?.flushPendingSave()
            DataStore.current = nil
            repo.configureForTesting()
            try? FileManager.default.removeItem(at: folder)
        }
        var store: DataStore? = DataStore(seedSampleData: false)
        store?.profile.healthKitNutritionEnabled = false
        store?.flushPendingSave()
        let date = Date()
        let entry = MealEntry(date: date, category: .breakfast, name: "Oats", calories: 200,
                              proteinG: 10, carbsG: 30, fatG: 4, source: .photo, components: [food().component])
        let before = store!.consumption(for: date).caloriesKcal
        repo.forceCommitFailureForTesting = true
        XCTAssertThrowsError(try store!.commitScannedMeals([entry]))
        XCTAssertFalse(store!.profile.mealHistory.contains { $0.id == entry.id })
        XCTAssertEqual(store!.consumption(for: date).caloriesKcal, before)
        XCTAssertFalse(repo.loadProfile()!.mealHistory.contains { $0.id == entry.id })
        repo.forceCommitFailureForTesting = false
        try store!.commitScannedMeals([entry, entry])
        try store!.commitScannedMeals([entry])
        XCTAssertEqual(store!.profile.mealHistory.filter { $0.id == entry.id }.count, 1)
        XCTAssertEqual(store!.consumption(for: date).caloriesKcal, before + 200)
        store?.flushPendingSave()
        DataStore.current = nil
        store = nil
        try repo.configurePersistentStoreForTesting(at: url)
        store = DataStore(seedSampleData: false)
        XCTAssertEqual(store!.profile.mealHistory.first { $0.id == entry.id }?.components, entry.components)
        repo.forceCommitFailureForTesting = true
        XCTAssertThrowsError(try store!.commitScannedMeals([entry], undo: true))
        XCTAssertTrue(store!.profile.mealHistory.contains { $0.id == entry.id })
        repo.forceCommitFailureForTesting = false
        try store!.commitScannedMeals([entry], undo: true)
        try store!.commitScannedMeals([entry], undo: true)
        XCTAssertEqual(store!.consumption(for: date).caloriesKcal, before)
        XCTAssertFalse(store!.profile.mealHistory.contains { $0.id == entry.id })
    }

    func testLegacyMealAndUnknownNutrientsStayUnknown() throws {
        let entry = MealEntry(date: Date(), category: .breakfast, name: "Legacy", calories: 200,
                              proteinG: 10, carbsG: 30, fatG: 4, source: .manual)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "components")
        let decoded = try JSONDecoder().decode(MealEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertNil(decoded.components)
        XCTAssertNil(decoded.fiberG)
        XCTAssertNil(MealFoodComponent.completeTotal([0, nil]))
        XCTAssertEqual(MealFoodComponent.completeTotal([0, 0]), 0)
    }

    func testReplacementAndNutrientCoveragePreservePortionAndSource() throws {
        let source = CustomFood(name: "Rice", per100g: .init(calories: 120, proteinG: 3, carbsG: 25,
            fatG: 1, fiberG: 2, sugarsG: 0)).toScannedProduct()
        var item = food()
        let originalID = item.id
        item.grams = 150
        item.replace(with: source)
        XCTAssertEqual(item.id, originalID)
        XCTAssertEqual(item.grams, 150)
        XCTAssertEqual(item.calories, 180)
        XCTAssertEqual(item.component.fiberG, 3)
        XCTAssertEqual(item.component.sugarsG, 0)
        let meal = try XCTUnwrap(source.loggable(for: .grams(150)))
        let entry = MealEntry(loggable: meal, name: source.name, category: .lunch, source: .custom)
        XCTAssertEqual(entry.fiberG, 3)
        let repeated = LifestyleDataLogic.relogged(entry, at: Date())
        XCTAssertNotEqual(repeated.id, entry.id)
        XCTAssertEqual(repeated.components, entry.components)
        let missing = MealEntry(date: Date(), category: .lunch, name: "Unknown", calories: 100,
                               proteinG: 0, carbsG: 0, fatG: 0, source: .manual)
        let coverage = MealNutrientCoverage.derive(entries: [entry, missing], nutrient: \.fiberG)
        XCTAssertEqual(coverage.total, 3)
        XCTAssertEqual(coverage.missing, 1)
        item.resetNutrition()
        XCTAssertEqual(item.name, "Oats")
        XCTAssertEqual(item.grams, 150)
        XCTAssertEqual(item.calories, 150)
        XCTAssertNil(item.replacementSourceID)
    }
}
