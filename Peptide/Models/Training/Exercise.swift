import Foundation

/// Immutable exercise record bundled with the app. Schema mirrors the
/// public-domain `yuhonas/free-exercise-db` dataset
/// (https://github.com/yuhonas/free-exercise-db, Unlicense), which is
/// loaded once at launch by `ExerciseLibrary` from
/// `Peptide/Resources/exercises.json`.
///
/// The raw string fields (`force`, `level`, `mechanic`, `equipment`,
/// `category`, muscle names) come directly from the dataset's vocabulary
/// and are surfaced verbatim on the exercise detail screen. The
/// `MuscleGroup` and `EquipmentKind` collapsed enums sit above the raw
/// strings to drive the filter chip row.
///
/// User-created exercises live in a separate SwiftData `@Model` so this
/// type can stay a pure `Codable Sendable` value loaded from the bundle.
struct Exercise: Codable, Hashable, Identifiable, Sendable {
    /// Slug-style identifier from the upstream dataset, e.g.
    /// `Decline_EZ_Bar_Triceps_Extension`. Stable across dataset
    /// versions so favorites and PRs keyed by id survive a dataset
    /// refresh.
    let id: String
    let name: String
    /// `push` / `pull` / `static` / nil — nil for exercises where the
    /// dataset doesn't have a directional load (e.g. stretches).
    let force: Force?
    let level: Level
    /// `compound` / `isolation` / nil — nil for stretching, cardio, etc.
    let mechanic: Mechanic?
    /// Raw equipment string from the dataset. Use `equipmentKind` for
    /// the collapsed enum used in filters.
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: Category
    /// Image paths relative to the dataset's `exercises/` root, e.g.
    /// `Decline_EZ_Bar_Triceps_Extension/0.jpg`. Two per exercise
    /// (start + end position). Retained as source provenance only; the app
    /// draws every exercise as the body map (`ExerciseAnatomyEngine`).
    let images: [String]

    enum Force: String, Codable, Sendable {
        case push, pull, `static`
    }

    enum Level: String, Codable, Sendable {
        case beginner, intermediate, expert
    }

    enum Mechanic: String, Codable, Sendable {
        case compound, isolation
    }

    enum Category: String, Codable, Sendable {
        case strength
        case stretching
        case plyometrics
        case strongman
        case powerlifting
        case cardio
        /// Dataset spells it "olympic weightlifting" — preserve the space
        /// via the raw value so encoding round-trips without a custom
        /// coding strategy.
        case olympicWeightlifting = "olympic weightlifting"
    }
}

extension Exercise {
    /// Collapsed muscle taxonomy used to drive the 9-chip filter row.
    /// Reads the first primary muscle when present, otherwise the first
    /// secondary, otherwise `.fullBody`. A lift whose primary + secondary
    /// muscles span `fullBodyGroupThreshold` collapsed groups (cleans,
    /// snatches, stone loads) is full-body; counting raw muscles instead
    /// filed squats and rows there too.
    var muscleGroup: MuscleGroup {
        if category != .strength && category != .powerlifting && category != .strongman && category != .olympicWeightlifting {
            return .cardioMobility
        }
        let groups = Set((primaryMuscles + secondaryMuscles).compactMap(MuscleGroup.fromRaw))
        if groups.count >= Self.fullBodyGroupThreshold {
            return .fullBody
        }
        if let primary = primaryMuscles.first,
           let group = MuscleGroup.fromRaw(primary) {
            return group
        }
        if let secondary = secondaryMuscles.first,
           let group = MuscleGroup.fromRaw(secondary) {
            return group
        }
        return .fullBody
    }

    static let fullBodyGroupThreshold = 5

    /// A user-made exercise lifted by `CustomExercise.asExercise()`.
    var isCustom: Bool { id.hasPrefix(CustomExercise.idPrefix) }

    /// The kit this exercise is done with, read from the raw equipment
    /// string and the name together — see `EquipmentClassificationEngine`.
    var equipmentKind: EquipmentKind {
        EquipmentClassificationEngine.kind(for: self)
    }

    /// Bench, rack, pull-up bar or box the exercise also needs.
    var equipmentAccessories: Set<EquipmentAccessory> {
        EquipmentClassificationEngine.accessories(for: self)
    }
}
