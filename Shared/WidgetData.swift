import Foundation

enum AppGroup {
    static let identifier = "group.com.peptidesai.app"
}

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
    /// Per-category breakdown for the Medium nutrition widget. Empty
    /// on legacy payloads written before this branch — the small
    /// widget renders fine without it.
    let mealsByCategory: [WidgetMealSlot]

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
        mealsByCategory: [WidgetMealSlot] = []
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
        self.mealsByCategory = mealsByCategory
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

    static let empty = WidgetData(
        nextPeptideName: "",
        nextDose: "",
        nextDoseTime: nil,
        completedToday: 0,
        totalToday: 0,
        lastUpdated: .distantPast
    )

    // MARK: - Codable (backwards-compatible: every nutrition field is
    // optional so older payloads written before the nutrition widget
    // shipped still decode cleanly into zeroed values).

    private enum CodingKeys: String, CodingKey {
        case nextPeptideName, nextDose, nextDoseTime
        case completedToday, totalToday, lastUpdated, upcoming
        case caloriesToday, calorieTarget
        case proteinToday, carbsToday, fatToday
        case mealsByCategory
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
        mealsByCategory = try c.decodeIfPresent([WidgetMealSlot].self, forKey: .mealsByCategory) ?? []
    }
}
