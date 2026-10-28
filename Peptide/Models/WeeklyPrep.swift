import Foundation

/// One ISO week of meal prep ("Veckoprep"): the dishes cooked on prep day,
/// what has been bought and which prep tasks are done. Device-local Codable
/// state in `WeeklyPrepStore`, like the pantry.
struct PrepWeek: Codable, Hashable, Sendable {
    /// Monday 00:00 of the ISO week.
    let weekStart: Date
    var dishes: [PrepDish] = []
    /// Pantry keys ticked off on the shopping list.
    var bought: Set<String> = []
    /// `PrepTask.id`s ticked off on the prep-day checklist.
    var doneTasks: Set<String> = []
    /// Set when the boxes went into the fridge; the plan is fixed from then.
    var preppedAt: Date?

    var recipeIDs: [String] { dishes.map(\.recipeID) }
}

/// A library recipe cooked in a batch of `servings` boxes.
struct PrepDish: Codable, Hashable, Identifiable, Sendable {
    let recipeID: String
    var servings: Int

    var id: String { recipeID }
}

/// Boxes of one dish cooked at the same time and kept in the same place.
/// Counted rather than listed one by one: four identical boxes are one row.
struct PrepBoxBatch: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let recipeID: String
    let cookedAt: Date
    /// Set when the boxes went into the freezer.
    var frozenAt: Date?
    var count: Int

    var isFrozen: Bool { frozenAt != nil }
}
