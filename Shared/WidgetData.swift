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

struct WidgetData: Codable, Equatable, Sendable {
    let nextPeptideName: String
    let nextDose: String
    let nextDoseTime: Date?
    let completedToday: Int
    let totalToday: Int
    var lastUpdated: Date
    let upcoming: [WidgetDoseSlot]
    /// Whether any protocol is active, whether or not it doses today.
    /// A rest day of a three-times-a-week protocol has no doses, and
    /// without this the widget can't tell it from having no protocol.
    let hasActiveProtocol: Bool
    // MARK: - Nutrition (Phase 7 — nutrition widget)
    /// Today's calorie consumption sum. Zero when nothing's logged.
    var caloriesToday: Int
    /// User's calorie target. Zero when the user hasn't picked one
    /// yet — the widget hides the "X / Y" line in that case.
    let calorieTarget: Int
    var proteinToday: Int
    var carbsToday: Int
    var fatToday: Int
    /// Macro targets in grams. Zero when the user hasn't set one — the
    /// widget then shows the gram count without a progress bar.
    let proteinTarget: Int
    let carbsTarget: Int
    let fatTarget: Int
    /// Per-category breakdown for the Medium nutrition widget. Empty
    /// on legacy payloads written before this branch — the small
    /// widget renders fine without it.
    var mealsByCategory: [WidgetMealSlot]

    // MARK: - Training
    /// Most recent finished workout. Nil until the user finishes one —
    /// the widget shows its "start a workout" empty state.
    let lastWorkout: WidgetWorkoutSummary?
    /// Finished sessions in the current calendar week.
    var workoutsThisWeek: Int
    /// Completed working sets across those sessions.
    var weeklySetCount: Int
    /// Their combined volume, in canonical kilograms.
    var weeklyVolumeKg: Double
    /// Start time of the workout in progress, or nil when none is.
    /// One field rather than a Bool plus a Date, which can disagree.
    var activeWorkoutStartedAt: Date?
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
    var trainingDaysThisWeek: [Date]
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
        hasActiveProtocol: Bool = false,
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
        self.hasActiveProtocol = hasActiveProtocol
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

    /// How long the payload can go unwritten before a running workout
    /// in it counts as abandoned. Mirrors
    /// `WorkoutStalenessEngine.loggedIdleLimit`, which closes such a
    /// session — but only once the app launches again.
    static let abandonedWorkoutAge: TimeInterval = 6 * 3600

    /// Where the running workout's clock counts from: its start shifted
    /// by the time spent paused, so a timer drawn from it agrees with
    /// the app after a pause and resume. Nil when no workout is running.
    var activeWorkoutClockStart: Date? {
        activeWorkoutStartedAt?.addingTimeInterval(activeWorkoutPausedSeconds)
    }

    /// Elapsed seconds frozen at the open pause, or nil while the clock
    /// runs or no workout is running.
    var activeWorkoutPausedElapsed: Int? {
        guard let start = activeWorkoutStartedAt, let pausedAt = activeWorkoutPausedAt else { return nil }
        return max(0, Int(pausedAt.timeIntervalSince(start) - activeWorkoutPausedSeconds))
    }

    /// Whether the dose half of the payload belongs to an earlier day.
    /// Only a payload that carried a protocol can be out of date; one
    /// without falls through to the no-protocol state rather than
    /// nagging a user who has nothing to load. Payloads written before
    /// `hasActiveProtocol` existed fall back to today's doses.
    func isProtocolOutdated(at now: Date, calendar: Calendar = .current) -> Bool {
        let carriedProtocol = hasActiveProtocol || totalToday > 0 || nextDoseTime != nil
        return carriedProtocol && !calendar.isDate(lastUpdated, inSameDayAs: now)
    }

    /// The payload as it reads at `now`, for an app that hasn't written
    /// since. Intake logged on an earlier day starts the new day at zero
    /// against the same targets; the week's training figures reset in a
    /// new week; a workout left running past `abandonedWorkoutAge` is
    /// dropped, or its timer would count for days. The dose fields are
    /// left alone: `isProtocolOutdated(at:)` says when they are stale.
    func forDisplay(at now: Date, calendar: Calendar = .current) -> WidgetData {
        var copy = self
        if now.timeIntervalSince(lastUpdated) > Self.abandonedWorkoutAge {
            copy.activeWorkoutStartedAt = nil
        }
        if !calendar.isDate(lastUpdated, equalTo: now, toGranularity: .weekOfYear) {
            copy.workoutsThisWeek = 0
            copy.weeklySetCount = 0
            copy.weeklyVolumeKg = 0
            copy.trainingDaysThisWeek = []
        }
        guard !calendar.isDate(lastUpdated, inSameDayAs: now) else { return copy }
        copy.caloriesToday = 0
        copy.proteinToday = 0
        copy.carbsToday = 0
        copy.fatToday = 0
        copy.mealsByCategory = mealsByCategory.map {
            WidgetMealSlot(category: $0.category, calories: 0, entryCount: 0)
        }
        return copy
    }

    /// The next widget reload: in `minutes`, or at midnight if that
    /// comes first, so a new day never waits on the reload to start.
    static func nextRefresh(after now: Date, minutes: Int = 15, calendar: Calendar = .current) -> Date {
        let soon = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
        return min(soon, nextMidnight(after: now, calendar: calendar))
    }

    /// Start of the day after `now`. A timeline entry here rolls the
    /// widget over even when WidgetKit defers the reload past midnight.
    static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    }

    /// True when every field but `lastUpdated` matches — rewriting
    /// such a payload would only spend the widgets' reload budget.
    func hasSameContent(as other: WidgetData) -> Bool {
        var restamped = other
        restamped.lastUpdated = lastUpdated
        return restamped == self
    }

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
        case completedToday, totalToday, lastUpdated, upcoming, hasActiveProtocol
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
        hasActiveProtocol = try c.decodeIfPresent(Bool.self, forKey: .hasActiveProtocol) ?? false
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
