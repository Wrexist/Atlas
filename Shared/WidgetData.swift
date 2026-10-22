import Foundation

/// One row in the Medium widget's "today" list. Three of these are
/// surfaced — enough to fill the widget without truncation under default
/// Dynamic Type, per `docs/SCREENSHOT_SEED_DATA_AND_FIXES.md` slot 7.
struct WidgetDoseSlot: Codable, Hashable, Sendable {
    let peptideName: String
    let dose: String
    let time: Date
    let completed: Bool
}

/// Per-meal-category breakdown surfaced on the Medium nutrition
/// widget. Mirrors the `MealCategoriesCard` totals from the Meals
/// tab (computed via `LifestyleDataLogic.CategoryTotals`) stripped
/// to the fields the widget actually renders so the
/// shared-container payload stays compact.
struct WidgetMealSlot: Codable, Hashable, Sendable {
    let category: String        // "Breakfast" / "Lunch" / "Dinner" / "Snack"
    let calories: Int
    let entryCount: Int
}

struct WidgetData: Codable, Sendable {
    let nextPeptideName: String
    let nextDose: String
    let nextDoseTime: Date?
    let completedToday: Int
    let totalToday: Int
    let lastUpdated: Date
    let upcoming: [WidgetDoseSlot]
    // MARK: - Nutrition (Phase 7 — nutrition widget)
    /// Today's calorie consumption sum. Zero when nothing's logged.
    let caloriesToday: Int
    /// User's calorie target. Zero when the user hasn't picked one
    /// yet — the widget hides the "X / Y" line in that case.
    let calorieTarget: Int
    let proteinToday: Int
    let carbsToday: Int
    let fatToday: Int
    /// Macro targets in grams. Zero when the user hasn't set one — the
    /// widget then shows the gram count without a progress bar.
    let proteinTarget: Int
    let carbsTarget: Int
    let fatTarget: Int
    /// Per-category breakdown for the Medium nutrition widget. Empty
    /// on legacy payloads written before this branch — the small
    /// widget renders fine without it.
    let mealsByCategory: [WidgetMealSlot]

    // MARK: - Training
    /// Most recent finished workout. Nil until the user finishes one —
    /// the widget shows its "start a workout" empty state.
    let lastWorkout: WidgetWorkoutSummary?
    /// Finished sessions in the current calendar week.
    let workoutsThisWeek: Int
    /// Completed working sets across those sessions.
    let weeklySetCount: Int
    /// Their combined volume, in canonical kilograms.
    let weeklyVolumeKg: Double
    /// Start time of the workout in progress, or nil when none is.
    /// One field rather than a Bool plus a Date, which can disagree.
    let activeWorkoutStartedAt: Date?
    /// Seconds the running workout has spent paused, before any pause
    /// still open. The widget's live timer counts from
    /// `activeWorkoutStartedAt` shifted by this, so it agrees with the
    /// in-app clock after a pause and resume.
    let activeWorkoutPausedSeconds: Double
    /// When the open pause began, or nil while the clock runs. The
    /// widget freezes its time here instead of ticking on.
    let activeWorkoutPausedAt: Date?
    /// Start of each day this week with at least one finished session.
    /// Feeds the training widget's Monday-to-Sunday strip.
    let trainingDaysThisWeek: [Date]
    /// `MeasurementUnit` rawValue — "metric" or "imperial". A String
    /// for the reason `WatchData.measurementUnit` is one: this file
    /// compiles into the widget targets, which can't see the app's
    /// model types. Volume is stored in kilograms, so without it an
    /// imperial user reads someone else's numbers.
    let measurementUnit: String

    init(
        nextPeptideName: String,
        nextDose: String,
        nextDoseTime: Date?,
        completedToday: Int,
        totalToday: Int,
        lastUpdated: Date,
        upcoming: [WidgetDoseSlot] = [],
        caloriesToday: Int = 0,
        calorieTarget: Int = 0,
        proteinToday: Int = 0,
        carbsToday: Int = 0,
        fatToday: Int = 0,
        proteinTarget: Int = 0,
        carbsTarget: Int = 0,
        fatTarget: Int = 0,
        mealsByCategory: [WidgetMealSlot] = [],
        lastWorkout: WidgetWorkoutSummary? = nil,
        workoutsThisWeek: Int = 0,
        weeklySetCount: Int = 0,
        weeklyVolumeKg: Double = 0,
        activeWorkoutStartedAt: Date? = nil,
        activeWorkoutPausedSeconds: Double = 0,
        activeWorkoutPausedAt: Date? = nil,
        trainingDaysThisWeek: [Date] = [],
        measurementUnit: String = "metric"
    ) {
        self.nextPeptideName = nextPeptideName
        self.nextDose = nextDose
        self.nextDoseTime = nextDoseTime
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.lastUpdated = lastUpdated
        self.upcoming = upcoming
        self.caloriesToday = caloriesToday
        self.calorieTarget = calorieTarget
        self.proteinToday = proteinToday
        self.carbsToday = carbsToday
        self.fatToday = fatToday
        self.proteinTarget = proteinTarget
        self.carbsTarget = carbsTarget
        self.fatTarget = fatTarget
        self.mealsByCategory = mealsByCategory
        self.lastWorkout = lastWorkout
        self.workoutsThisWeek = workoutsThisWeek
        self.weeklySetCount = weeklySetCount
        self.weeklyVolumeKg = weeklyVolumeKg
        self.activeWorkoutStartedAt = activeWorkoutStartedAt
        self.activeWorkoutPausedSeconds = activeWorkoutPausedSeconds
        self.activeWorkoutPausedAt = activeWorkoutPausedAt
        self.trainingDaysThisWeek = trainingDaysThisWeek
        self.measurementUnit = measurementUnit
    }

    var compliance: Double {
        totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
    }

    /// Fraction of the day's calorie target consumed. Clamped at 1.0
    /// so the widget ring never overdraws past full when the user
    /// exceeds their target.
    var calorieProgress: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(1.0, Double(caloriesToday) / Double(calorieTarget))
    }

    /// True while a workout is in progress — the training widget swaps
    /// to a live elapsed-time layout.
    var workoutInProgress: Bool { activeWorkoutStartedAt != nil }

    /// Weight-unit suffix, mirroring `MeasurementUnit.weightSuffix`.
    /// Deliberately unlocalised: "kg" and "lb" are the symbols in every
    /// locale Atlas ships.
    var weightSuffix: String { measurementUnit == "imperial" ? "lb" : "kg" }

    /// Canonical kilograms → the number to put on screen.
    func volumeInUserUnit(_ kilograms: Double) -> Double {
        measurementUnit == "imperial" ? kilograms * 2.20462 : kilograms
    }

    static let empty = WidgetData(
        nextPeptideName: "",
        nextDose: "",
        nextDoseTime: nil,
        completedToday: 0,
        totalToday: 0,
        lastUpdated: .distantPast
    )

    // MARK: - Codable (backwards-compatible: every nutrition and
    // training field is optional so older payloads — written before
    // those widgets shipped — still decode cleanly into zeroed values).

    private enum CodingKeys: String, CodingKey {
        case nextPeptideName, nextDose, nextDoseTime
        case completedToday, totalToday, lastUpdated, upcoming
        case caloriesToday, calorieTarget
        case proteinToday, carbsToday, fatToday
        case proteinTarget, carbsTarget, fatTarget
        case mealsByCategory
        case lastWorkout, workoutsThisWeek, weeklySetCount, weeklyVolumeKg
        case activeWorkoutStartedAt, activeWorkoutPausedSeconds, activeWorkoutPausedAt
        case trainingDaysThisWeek, measurementUnit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextPeptideName = try c.decode(String.self, forKey: .nextPeptideName)
        nextDose = try c.decode(String.self, forKey: .nextDose)
        nextDoseTime = try c.decodeIfPresent(Date.self, forKey: .nextDoseTime)
        completedToday = try c.decode(Int.self, forKey: .completedToday)
        totalToday = try c.decode(Int.self, forKey: .totalToday)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        upcoming = try c.decodeIfPresent([WidgetDoseSlot].self, forKey: .upcoming) ?? []
        caloriesToday = try c.decodeIfPresent(Int.self, forKey: .caloriesToday) ?? 0
        calorieTarget = try c.decodeIfPresent(Int.self, forKey: .calorieTarget) ?? 0
        proteinToday = try c.decodeIfPresent(Int.self, forKey: .proteinToday) ?? 0
        carbsToday = try c.decodeIfPresent(Int.self, forKey: .carbsToday) ?? 0
        fatToday = try c.decodeIfPresent(Int.self, forKey: .fatToday) ?? 0
        proteinTarget = try c.decodeIfPresent(Int.self, forKey: .proteinTarget) ?? 0
        carbsTarget = try c.decodeIfPresent(Int.self, forKey: .carbsTarget) ?? 0
        fatTarget = try c.decodeIfPresent(Int.self, forKey: .fatTarget) ?? 0
        mealsByCategory = try c.decodeIfPresent([WidgetMealSlot].self, forKey: .mealsByCategory) ?? []
        lastWorkout = try c.decodeIfPresent(WidgetWorkoutSummary.self, forKey: .lastWorkout)
        workoutsThisWeek = try c.decodeIfPresent(Int.self, forKey: .workoutsThisWeek) ?? 0
        weeklySetCount = try c.decodeIfPresent(Int.self, forKey: .weeklySetCount) ?? 0
        weeklyVolumeKg = try c.decodeIfPresent(Double.self, forKey: .weeklyVolumeKg) ?? 0
        activeWorkoutStartedAt = try c.decodeIfPresent(Date.self, forKey: .activeWorkoutStartedAt)
        activeWorkoutPausedSeconds = try c.decodeIfPresent(Double.self, forKey: .activeWorkoutPausedSeconds) ?? 0
        activeWorkoutPausedAt = try c.decodeIfPresent(Date.self, forKey: .activeWorkoutPausedAt)
        trainingDaysThisWeek = try c.decodeIfPresent([Date].self, forKey: .trainingDaysThisWeek) ?? []
        measurementUnit = try c.decodeIfPresent(String.self, forKey: .measurementUnit) ?? "metric"
    }
}
