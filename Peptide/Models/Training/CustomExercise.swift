import Foundation

/// User-created exercise. Mirrors enough of `Exercise`'s shape that
/// the UI can render either side-by-side without branching: routines
/// and sessions reference both kinds by a string id, and
/// `ExerciseLibrary.lookup(id:)` resolves the id against the bundled
/// dataset first, then custom storage.
///
/// Stored as a SwiftData `@Model` via `StoredCustomExercise` (defined
/// in `SwiftDataModels+Training.swift`); this value type is the
/// in-memory shape passed around by services and views.
struct CustomExercise: Codable, Hashable, Identifiable, Sendable {
    /// Stable string id prefixed `custom_` so it never collides with
    /// the bundled dataset's slug-style ids. Generated on create.
    let id: String
    var name: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    /// Raw equipment string. Defaults to `body only` for the bodyweight
    /// floor so the equipment chip resolves cleanly.
    var equipment: String?
    var instructions: [String]
    var createdAt: Date

    init(
        id: String = "custom_\(UUID().uuidString)",
        name: String,
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        equipment: String? = "body only",
        instructions: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instructions = instructions
        self.createdAt = createdAt
    }

    /// Lift this custom record into the same shape as a bundled
    /// exercise so the UI can render them interchangeably. Custom
    /// exercises have no images and no force/mechanic metadata in v1
    /// — the field is `nil` and the detail screen falls back to an SF
    /// Symbol placeholder.
    func asExercise() -> Exercise {
        Exercise(
            id: id,
            name: name,
            force: nil,
            level: .beginner,
            mechanic: nil,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            instructions: instructions,
            category: .strength,
            images: []
        )
    }
}
