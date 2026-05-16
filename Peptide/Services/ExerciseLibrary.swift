import Foundation
import OSLog

/// In-memory exercise catalog. Loads the bundled JSON dataset
/// (`exercises.json` — yuhonas/free-exercise-db, Unlicense) on first
/// access, caches the decoded array for the lifetime of the process,
/// and exposes synchronous fuzzy search + filter helpers used by the
/// Train tab.
///
/// Custom user-created exercises live in a SwiftData store and are
/// merged in via `attachCustomExercises(_:)` — kept separate so the
/// bundled catalog can stay an immutable lookup table.
@MainActor @Observable
final class ExerciseLibrary {

    static let shared = ExerciseLibrary()

    /// Bundled dataset. Empty until `load()` runs (called lazily on
    /// first read).
    private(set) var bundled: [Exercise] = []

    /// User-created exercises, merged on top of `bundled`. Mutated via
    /// `attachCustomExercises(_:)`; the Train tab pulls them out of
    /// SwiftData on appear and pushes them in.
    private(set) var custom: [CustomExercise] = []

    private var byID: [String: Exercise] = [:]
    private var isLoaded = false

    private init() {}

    // MARK: - Loading

    /// Loads the bundled JSON. Idempotent on success — safe to call on
    /// every `.task { }` modifier in the Train tab without re-decoding.
    /// On decode failure `isLoaded` stays `false` so a follow-up call
    /// (typically the empty-state retry button) re-attempts the parse.
    /// Bundled-resource failures are rare but recoverable filesystem
    /// hiccups (incomplete OTA, App Store CDN glitch) shouldn't lock
    /// the user out of training permanently.
    func load() async {
        guard !isLoaded else { return }
        let started = Date()
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            AppLog.training.error("ExerciseLibrary: exercises.json missing from bundle")
            return
        }
        // Move the read + decode off the main actor. The bundled JSON is
        // ~800 KB; on older devices the synchronous Data(contentsOf:) +
        // JSONDecoder runs visibly stalled the first Train tab open.
        let parsed: [Exercise]? = await Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([Exercise].self, from: data)
            } catch {
                AppLog.training.error("ExerciseLibrary decode failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
        guard let decoded = parsed else { return }
        bundled = decoded
        byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        isLoaded = true
        AppLog.training.info(
            "ExerciseLibrary loaded \(decoded.count, privacy: .public) exercises in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public)ms"
        )
    }

    /// Forces a re-load on the next `load()` call. Used by tests and by
    /// the empty-state retry button to recover from a transient
    /// bundled-resource failure.
    func reset() {
        isLoaded = false
        bundled = []
        byID = [:]
    }

    /// Replaces the custom-exercise overlay. Called by the Train tab
    /// after fetching the user's `StoredCustomExercise` rows.
    func attachCustomExercises(_ exercises: [CustomExercise]) {
        custom = exercises
    }

    // MARK: - Lookup

    /// Resolves an exercise id to its display record. Searches the
    /// bundled dataset first, then the custom overlay (lifted via
    /// `asExercise()` so the caller sees a uniform shape). Returns
    /// `nil` for an unknown id — callers should render a placeholder
    /// rather than crash.
    func lookup(id: String) -> Exercise? {
        if let hit = byID[id] { return hit }
        if let custom = custom.first(where: { $0.id == id }) {
            return custom.asExercise()
        }
        return nil
    }

    // MARK: - Filtering & search

    /// Full filterable view used by the exercise picker. All
    /// parameters are optional / additive — an unset filter is the
    /// identity. Bundled and custom records are unioned; results are
    /// sorted by `name` for a stable list order.
    ///
    /// `query` is matched case-insensitively against the exercise
    /// name, raw muscle strings, and the equipment string — covers
    /// the obvious "bench press", "lat", "kettlebell" queries without
    /// dragging in a full-text index.
    func filter(
        query: String? = nil,
        muscleGroup: MuscleGroup? = nil,
        equipment: EquipmentKind? = nil,
        category: Exercise.Category? = nil,
        level: Exercise.Level? = nil
    ) -> [Exercise] {
        let needle = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let needleEmpty = needle?.isEmpty ?? true

        let merged = bundled + custom.map { $0.asExercise() }

        return merged
            .filter { exercise in
                if let group = muscleGroup, exercise.muscleGroup != group {
                    return false
                }
                if let equipment, exercise.equipmentKind != equipment {
                    return false
                }
                if let category, exercise.category != category {
                    return false
                }
                if let level, exercise.level != level {
                    return false
                }
                if !needleEmpty, let needle {
                    if !exerciseMatchesQuery(exercise, needle: needle) {
                        return false
                    }
                }
                return true
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// True when any of the exercise's searchable fields contains the
    /// pre-lowercased needle. Pulled out for readability and to keep
    /// the hot path in `filter(...)` tight.
    private func exerciseMatchesQuery(_ exercise: Exercise, needle: String) -> Bool {
        if exercise.name.lowercased().contains(needle) { return true }
        for muscle in exercise.primaryMuscles where muscle.lowercased().contains(needle) {
            return true
        }
        for muscle in exercise.secondaryMuscles where muscle.lowercased().contains(needle) {
            return true
        }
        if let equipment = exercise.equipment, equipment.lowercased().contains(needle) {
            return true
        }
        return false
    }

    /// Returns exercises whose `equipmentKind` is in the user's
    /// configured equipment access set. Used by the program
    /// recommendation engine and by the routine editor's "only show
    /// what I can actually do" toggle.
    func availableForEquipment(_ access: Set<EquipmentKind>) -> [Exercise] {
        guard !access.isEmpty else { return bundled + custom.map { $0.asExercise() } }
        return (bundled + custom.map { $0.asExercise() })
            .filter { access.contains($0.equipmentKind) }
    }
}
