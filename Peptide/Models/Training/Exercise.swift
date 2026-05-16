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
/// strings to drive the filter chip row — see their `from(raw:)` helpers.
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
    /// (start + end position). Resolved through `ExerciseImageResolver`
    /// so the URL host can switch between bundled / CDN without a
    /// schema migration.
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
    /// secondary, otherwise `.fullBody`. An exercise tagged with four or
    /// more distinct primary + secondary muscles is treated as full-body
    /// regardless of its first tag (matches the planning doc).
    var muscleGroup: MuscleGroup {
        let distinct = Set(primaryMuscles + secondaryMuscles)
        if distinct.count >= 4 && category == .strength {
            return .fullBody
        }
        if category != .strength && category != .powerlifting && category != .strongman && category != .olympicWeightlifting {
            return .cardioMobility
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

    /// Collapsed equipment enum used for filter chips. Returns
    /// `.bodyweight` for missing / "none" equipment so the chip count
    /// matches the dataset's "no equipment needed" intuition.
    var equipmentKind: EquipmentKind {
        EquipmentKind.fromRaw(equipment)
    }

    /// Stable display force string for the detail screen. Returns the
    /// raw force value capitalized, or "Static" / "—" fallbacks.
    var forceDisplay: String {
        guard let force = force else { return "—" }
        return force.rawValue.prefix(1).uppercased() + force.rawValue.dropFirst()
    }
}
