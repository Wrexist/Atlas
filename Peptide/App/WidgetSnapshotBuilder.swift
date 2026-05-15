import Foundation

/// Pure builder for the home-screen / lock-screen widget payload.
/// Extracted from `DataStore.updateWidgetData` so the snapshot shape
/// is unit-testable and the side effects (PersistenceService write,
/// WidgetCenter reload) stay isolated on DataStore.
///
/// The widget target consumes the resulting `WidgetData` verbatim via
/// `PersistenceService.shared.loadWidgetData()`, so any drift in this
/// transformation surfaces immediately on the next render — there's
/// no schema migration between phone and widget.
enum WidgetSnapshotBuilder {

    /// Captures the inputs the widget cares about: today's entries
    /// (regardless of completion), the next pending dose, and the day's
    /// nutrition rollup. The next dose is passed separately rather than
    /// recomputed because `DataStore.nextDose` is cached and shouldn't
    /// be re-derived. Nutrition is optional so non-nutrition widgets
    /// (NextDose, Compliance) continue to work even on a fresh install
    /// where the user hasn't logged anything yet.
    static func build(
        today: [ProtocolEntry],
        next: ProtocolEntry?,
        consumption: DailyConsumption = .empty(on: Date()),
        targets: NutritionTargets? = nil,
        breakdown: LifestyleDataLogic.CategoryBreakdown? = nil
    ) -> WidgetData {
        let completed = today.filter(\.completed).count

        // Surface the next 3 doses (chronological) for the Medium widget's
        // today list — see slot 7 in docs/APP_STORE_SCREENSHOTS_GUIDE_1.md.
        let upcoming = today
            .sorted { $0.date < $1.date }
            .prefix(3)
            .map { entry in
                WidgetDoseSlot(
                    peptideName: entry.peptide.abbreviation,
                    dose: entry.dose,
                    time: entry.date,
                    completed: entry.completed
                )
            }

        let meals: [WidgetMealSlot]
        if let b = breakdown {
            // Names come from `MealCategory.displayName` so the widget
            // matches the in-app labels (and follows localization
            // through Xcode's string catalog) — previously the four
            // strings were duplicated as literals.
            meals = [
                WidgetMealSlot(category: MealCategory.breakfast.displayName, calories: b.breakfast.calories, entryCount: b.breakfast.entryCount),
                WidgetMealSlot(category: MealCategory.lunch.displayName,     calories: b.lunch.calories,     entryCount: b.lunch.entryCount),
                WidgetMealSlot(category: MealCategory.dinner.displayName,    calories: b.dinner.calories,    entryCount: b.dinner.entryCount),
                WidgetMealSlot(category: MealCategory.snack.displayName,     calories: b.snack.calories,     entryCount: b.snack.entryCount),
            ]
        } else {
            meals = []
        }

        return WidgetData(
            nextPeptideName: next?.peptide.abbreviation ?? "",
            nextDose: next?.dose ?? "",
            nextDoseTime: next?.date,
            completedToday: completed,
            totalToday: today.count,
            lastUpdated: Date(),
            upcoming: Array(upcoming),
            caloriesToday: consumption.caloriesKcal,
            calorieTarget: targets?.calories ?? 0,
            proteinToday: consumption.proteinG,
            carbsToday: consumption.carbsG,
            fatToday: consumption.fatG,
            mealsByCategory: meals
        )
    }
}
