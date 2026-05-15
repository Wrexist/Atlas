import Foundation

/// Which meal of the day a `MealEntry` belongs to. Drives the per-
/// category breakdown card on the Lifestyle tab and the (eventual)
/// HealthKit meal-type tagging.
///
/// Time-of-day auto-classification lives on `MealCategory.auto(for:)`
/// — used by the review screens as the default when the user hasn't
/// picked explicitly. The buckets match Lifesum/MyFitnessPal so a
/// user switching apps sees familiar labels.
enum MealCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch:     "Lunch"
        case .dinner:    "Dinner"
        case .snack:     "Snack"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .lunch:     "sun.max.fill"
        case .dinner:    "moon.stars.fill"
        case .snack:     "leaf.fill"
        }
    }

    /// Time-of-day default. Matches a typical Western eating pattern:
    /// 4–10:59 → breakfast, 11–15:59 → lunch, 16–21:59 → dinner,
    /// otherwise snack. Users can override on the review screen, but
    /// most don't — picking a sane default saves a tap per log.
    static func auto(for date: Date) -> MealCategory {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4...10:   return .breakfast
        case 11...15:  return .lunch
        case 16...21:  return .dinner
        default:       return .snack
        }
    }
}

/// Which entry path produced a meal log. Lets the analytics layer
/// (future) distinguish search-typed logs from camera-scanned ones,
/// and lets the meal-history UI render different icons per source
/// without sniffing the synthetic-barcode prefix every time.
enum MealSource: String, Codable, Sendable {
    /// Open Food Facts search or barcode hit. `sourceID` carries the
    /// product barcode for re-log shortcuts.
    case openFoodFacts
    /// User-defined food in `profile.customFoods`. `sourceID` carries
    /// the `custom:<uuid>` namespaced ID.
    case custom
    /// AI-estimated from a meal photo (`MealScannerService`). No
    /// sourceID — each scan is unique.
    case photo
    /// User typed the macros directly (the OFF flow's "edit
    /// nutrition" override, or a future "quick add" path). No
    /// sourceID.
    case manual

    var icon: String {
        switch self {
        case .openFoodFacts: "barcode"
        case .custom:        "person.crop.rectangle.stack"
        case .photo:         "camera.fill"
        case .manual:        "pencil"
        }
    }
}

/// One logged meal — the building block for per-meal history, the
/// per-category macro breakdown, and (when wired) HealthKit dietary-
/// energy samples.
///
/// Lives alongside `DailyConsumption` on `UserProfile`. The aggregate
/// still drives the macro rings (cheap O(1) read), and entries power
/// everything that needs per-meal detail. New logs write both so the
/// aggregate stays accurate without forcing the rings to recompute on
/// every render.
///
/// Legacy logs (pre-`MealEntry`) only updated the aggregate. When
/// computing per-category totals, anything not covered by `mealHistory`
/// gets bucketed as `Other` so the legacy rings still add up.
struct MealEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    var category: MealCategory
    var name: String
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    /// Barcode for OFF results, `custom:<uuid>` for custom foods, nil
    /// for photo / manual entries. Lets the history UI deep-link back
    /// into the same review sheet for a one-tap re-log.
    var sourceID: String?
    var source: MealSource

    init(
        id: UUID = UUID(),
        date: Date,
        category: MealCategory,
        name: String,
        calories: Int,
        proteinG: Int,
        carbsG: Int,
        fatG: Int,
        sourceID: String? = nil,
        source: MealSource
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sourceID = sourceID
        self.source = source
    }
}

extension MealEntry {
    /// Convenience for the LoggableMeal → MealEntry mapping used by
    /// every review screen. Pulls the integer macros + name and pairs
    /// them with the picked category and source.
    init(
        loggable: LoggableMeal,
        name: String,
        category: MealCategory,
        source: MealSource,
        sourceID: String? = nil,
        date: Date = Date()
    ) {
        self.init(
            date: date,
            category: category,
            name: name,
            calories: loggable.calories,
            proteinG: loggable.proteinG,
            carbsG: loggable.carbsG,
            fatG: loggable.fatG,
            sourceID: sourceID,
            source: source
        )
    }
}
