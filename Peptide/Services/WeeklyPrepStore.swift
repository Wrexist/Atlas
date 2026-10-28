import Foundation
import Observation

/// The user's weekly meal prep: a plan per ISO week and the boxes in the
/// fridge and freezer. Device-local Codable state in UserDefaults, like
/// `PantryStore`: what is in this kitchen's fridge is not worth a CloudKit
/// schema change. All the rules live in `WeeklyPrepEngine`.
@MainActor @Observable
final class WeeklyPrepStore {
    static let shared = WeeklyPrepStore()

    private static let storageKey = "weeklyPrep.state"
    @ObservationIgnored private let defaults: UserDefaults

    private(set) var plans: [PrepWeek]
    private(set) var boxes: [PrepBoxBatch]

    /// The bundled library, and the same by id.
    let library: [LibraryRecipe]
    let recipes: [String: LibraryRecipe]

    private struct State: Codable {
        var plans: [PrepWeek]
        var boxes: [PrepBoxBatch]
    }

    init(defaults: UserDefaults = .standard, library: [LibraryRecipe] = RecipeLibraryEngine.bundled) {
        self.defaults = defaults
        self.library = library
        recipes = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let state = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        plans = state?.plans ?? []
        boxes = state?.boxes ?? []
    }

    // MARK: - Plan

    func plan(now: Date = .now, calendar: Calendar = .current) -> PrepWeek {
        WeeklyPrepEngine.plan(for: now, in: plans, calendar: calendar)
    }

    /// Meal-prep recipes best first for this week, for the swap sheet.
    func ranked(context: RecipeLibraryEngine.Context) -> [LibraryRecipe] {
        let recent = WeeklyPrepEngine.recentRecipeIDs(in: plans, before: context.now, calendar: context.calendar)
        return WeeklyPrepEngine.ranked(library, context: context, recentRecipeIDs: recent)
    }

    func suggestWeek(context: RecipeLibraryEngine.Context) {
        let dishes = WeeklyPrepEngine.suggestWeek(from: ranked(context: context))
        update(now: context.now, calendar: context.calendar) { $0.dishes = dishes }
    }

    /// Puts `recipe` in place of `recipeID`, or adds it when `recipeID` is nil.
    func replace(_ recipeID: String?, with recipe: LibraryRecipe, now: Date = .now, calendar: Calendar = .current) {
        update(now: now, calendar: calendar) { plan in
            guard !plan.recipeIDs.contains(recipe.id) else { return }
            let dish = PrepDish(recipeID: recipe.id, servings: recipe.servings)
            if let recipeID, let index = plan.dishes.firstIndex(where: { $0.recipeID == recipeID }) {
                plan.dishes[index] = dish
            } else if plan.dishes.count < WeeklyPrepEngine.dishesPerWeek {
                plan.dishes.append(dish)
            }
        }
    }

    func setServings(_ servings: Int, for recipeID: String, now: Date = .now, calendar: Calendar = .current) {
        let range = WeeklyPrepEngine.servingRange
        update(now: now, calendar: calendar) { plan in
            guard let index = plan.dishes.firstIndex(where: { $0.recipeID == recipeID }) else { return }
            plan.dishes[index].servings = min(range.upperBound, max(range.lowerBound, servings))
        }
    }

    func toggleBought(_ pantryKey: String, now: Date = .now, calendar: Calendar = .current) {
        update(now: now, calendar: calendar) { plan in
            if plan.bought.remove(pantryKey) == nil { plan.bought.insert(pantryKey) }
        }
    }

    func toggleTask(_ taskID: String, now: Date = .now, calendar: Calendar = .current) {
        update(now: now, calendar: calendar) { plan in
            if plan.doneTasks.remove(taskID) == nil { plan.doneTasks.insert(taskID) }
        }
    }

    /// Prep day is done: each dish becomes a batch of boxes in the fridge.
    func finishPrep(now: Date = .now, calendar: Calendar = .current) {
        let current = plan(now: now, calendar: calendar)
        guard current.preppedAt == nil, !current.dishes.isEmpty else { return }
        boxes += WeeklyPrepEngine.boxes(for: current.dishes, cookedAt: now)
        update(now: now, calendar: calendar) { $0.preppedAt = now }
        boxesChanged()
    }

    private func update(now: Date, calendar: Calendar, _ change: (inout PrepWeek) -> Void) {
        var plan = self.plan(now: now, calendar: calendar)
        change(&plan)
        plans.removeAll { $0.weekStart == plan.weekStart }
        plans.append(plan)
        plans = WeeklyPrepEngine.pruned(plans, now: now, calendar: calendar)
        persist()
    }

    // MARK: - Boxes

    /// Boxes to show: fridge first, soonest eat-by first, long-expired ones gone.
    func visibleBoxes(now: Date = .now, calendar: Calendar = .current) -> [PrepBoxBatch] {
        let kept = WeeklyPrepEngine.pruned(boxes, recipes: recipes, now: now, calendar: calendar)
        return WeeklyPrepEngine.sorted(kept, recipes: recipes, calendar: calendar)
    }

    /// Eaten or thrown out: one box fewer.
    func removeOne(_ batchID: UUID) {
        boxes = WeeklyPrepEngine.removingOne(from: boxes, id: batchID)
        boxesChanged()
    }

    func freezeOne(_ batchID: UUID, now: Date = .now) {
        boxes = WeeklyPrepEngine.freezingOne(from: boxes, id: batchID, at: now)
        boxesChanged()
    }

    private func boxesChanged() {
        boxes = WeeklyPrepEngine.pruned(boxes, recipes: recipes, now: .now, calendar: .current)
        persist()
        let boxes = boxes
        let recipes = recipes
        Task { await PrepBoxReminderScheduler.reconcile(boxes: boxes, recipes: recipes) }
    }

    // MARK: - Storage

    /// "Delete all data" — the plan and boxes must not survive an erase.
    func deleteAll() {
        plans = []
        boxes = []
        defaults.removeObject(forKey: Self.storageKey)
        PrepBoxReminderScheduler.cancel()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(State(plans: plans, boxes: boxes)), forKey: Self.storageKey)
        } catch {
            AppLog.persistence.error("Weekly prep not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
