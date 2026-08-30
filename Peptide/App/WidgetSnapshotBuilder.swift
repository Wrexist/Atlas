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
        breakdown: LifestyleDataLogic.CategoryBreakdown? = nil,
        workouts: [WorkoutSession] = [],
        activeWorkout: WorkoutSession? = nil,
        unit: MeasurementUnit = .metric,
        now: Date = Date(),
        calendar: Calendar = .current
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

        let trainingFields = training(from: workouts, now: now, calendar: calendar)

        return WidgetData(
            nextPeptideName: next?.peptide.abbreviation ?? "",
            nextDose: next?.dose ?? "",
            nextDoseTime: next?.date,
            completedToday: completed,
            totalToday: today.count,
            lastUpdated: now,
            upcoming: Array(upcoming),
            caloriesToday: consumption.caloriesKcal,
            calorieTarget: targets?.calories ?? 0,
            proteinToday: consumption.proteinG,
            carbsToday: consumption.carbsG,
            fatToday: consumption.fatG,
            mealsByCategory: meals,
            lastWorkout: trainingFields.lastWorkout,
            workoutsThisWeek: trainingFields.workoutsThisWeek,
            weeklySetCount: trainingFields.weeklySetCount,
            weeklyVolumeKg: trainingFields.weeklyVolumeKg,
            // An in-progress session is reported here, never as
            // history — the widget's live layout keys off its presence.
            activeWorkoutStartedAt: activeWorkout.flatMap { $0.isActive ? $0.startedAt : nil },
            measurementUnit: unit.rawValue
        )
    }

    /// The training half of the payload. Separate from `build` because
    /// it's the only part with real derivation in it, and because the
    /// tests want to pin the week boundary without constructing a full
    /// dose + nutrition fixture.
    ///
    /// `workouts` is whatever recent slice the caller has to hand — it
    /// may include the in-progress session and sessions from earlier
    /// weeks. Both are filtered out here so the call site stays a
    /// single bounded fetch.
    static func training(
        from workouts: [WorkoutSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingSnapshot {
        let finished = workouts.filter { !$0.isActive }
        let thisWeek: [WorkoutSession]
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            thisWeek = finished.filter { week.contains($0.finishedAt ?? $0.startedAt) }
        } else {
            thisWeek = []
        }

        return TrainingSnapshot(
            lastWorkout: finished
                .max { lhs, rhs in
                    (lhs.finishedAt ?? .distantPast) < (rhs.finishedAt ?? .distantPast)
                }
                .map { summary(of: $0) },
            workoutsThisWeek: thisWeek.count,
            weeklySetCount: thisWeek.reduce(0) { $0 + $1.completedSetCount },
            weeklyVolumeKg: thisWeek.reduce(0) { $0 + $1.totalVolumeKg }
        )
    }

    /// The training fields of `WidgetData`, grouped so `build` reads as
    /// one assembly step rather than four.
    struct TrainingSnapshot: Equatable {
        var lastWorkout: WidgetWorkoutSummary?
        var workoutsThisWeek: Int
        var weeklySetCount: Int
        var weeklyVolumeKg: Double
    }

    private static func summary(of session: WorkoutSession) -> WidgetWorkoutSummary {
        // Callers filter to sealed sessions, so the fallback is only
        // ever reached if that invariant breaks — a zero-minute
        // workout beats a crash on the home screen.
        let finishedAt = session.finishedAt ?? session.startedAt
        return WidgetWorkoutSummary(
            name: session.name ?? "",
            finishedAt: finishedAt,
            setCount: session.completedSetCount,
            volumeKg: session.totalVolumeKg,
            durationMinutes: max(0, Int(finishedAt.timeIntervalSince(session.startedAt) / 60))
        )
    }
}
