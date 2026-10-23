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

    /// User-created exercises, merged on top of `bundled`. Read from
    /// SwiftData by `load()` and again by `reloadCustomExercises()`
    /// whenever the store changes underneath (CloudKit pull, backup
    /// restore, iCloud account switch).
    private(set) var custom: [CustomExercise] = []

    private var byID: [String: Exercise] = [:]
    /// Instruction steps in the app's language, keyed by bundled exercise
    /// id. Empty in English, where `Exercise.instructions` already is the
    /// text.
    private var translatedSteps: [String: [String]] = [:]
    /// Bundled + custom, sorted by name, with each row's filter keys
    /// worked out once. `filter` runs on every library render, so it
    /// must not re-classify or re-sort ~870 exercises per keystroke.
    private var catalog: [CatalogEntry] = []
    /// `private(set)` so views can distinguish "still loading" from
    /// "loaded, genuinely no match" instead of flashing a false
    /// not-found state before `load()` completes.
    private(set) var isLoaded = false

    private init() {}

    // MARK: - Instructions

    /// How to perform the exercise, in the app's language when a
    /// translation ships for it. Custom exercises keep the user's own text.
    func steps(for exercise: Exercise) -> [String] {
        translatedSteps[exercise.id] ?? exercise.instructions
    }

    /// `exercise-instructions.<language>.json`: bundled exercise id to its
    /// translated steps. English has no file, so this reads as empty.
    nonisolated static func translatedSteps(language: String, bundle: Bundle = .main) -> [String: [String]] {
        guard let url = bundle.url(forResource: "exercise-instructions.\(language)", withExtension: "json") else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        } catch {
            AppLog.training.error("ExerciseLibrary: \(language, privacy: .public) instructions failed to decode: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

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
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let parsed: ([Exercise], [String: [String]])? = await Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let exercises = try JSONDecoder().decode([Exercise].self, from: data)
                return (exercises, Self.translatedSteps(language: language))
            } catch {
                AppLog.training.error("ExerciseLibrary decode failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
        guard let parsed else { return }
        let (decoded, translations) = parsed
        bundled = decoded
        translatedSteps = translations
        // uniquingKeysWith (keep first) instead of uniqueKeysWithValues:
        // a duplicate id in a bad exercises.json edit/OTA would otherwise
        // trap and crash the app on launch.
        byID = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Rebuilds the catalog too. Without it a relaunch leaves every
        // custom exercise resolving to "Unknown exercise" until the user
        // happens to open a recap or create another one.
        reloadCustomExercises()
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
        rebuildCatalog()
    }

    /// Re-reads the user's `StoredCustomExercise` rows into the overlay.
    func reloadCustomExercises() {
        attachCustomExercises(SwiftDataRepository.shared.loadCustomExercises())
    }

    /// Replaces the custom-exercise overlay.
    func attachCustomExercises(_ exercises: [CustomExercise]) {
        custom = exercises
        rebuildCatalog()
    }

    private func rebuildCatalog() {
        catalog = (bundled + custom.map { $0.asExercise() })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(CatalogEntry.init)
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

    /// The name to show for an exercise id. A deleted or not-yet-loaded
    /// exercise reads as "Unknown exercise", never as its raw slug or UUID.
    func displayName(for id: String) -> String {
        lookup(id: id)?.name ?? String(localized: "Unknown exercise")
    }

    // MARK: - Filtering & search

    /// Full filterable view used by the exercise picker. All
    /// parameters are optional / additive — an unset filter is the
    /// identity. Bundled and custom records are unioned; results are
    /// sorted by `name` for a stable list order.
    ///
    /// `query` is split into words and every word must appear in the
    /// exercise name, a raw muscle string or the equipment string, so
    /// "dumbbell press" and "press dumbbell" both find "Dumbbell Bench
    /// Press". Case, diacritics and hyphens are ignored ("pull-up",
    /// "pull up" and "pullup" all match).
    func filter(
        query: String? = nil,
        muscleGroup: MuscleGroup? = nil,
        equipment: EquipmentKind? = nil,
        category: Exercise.Category? = nil,
        level: Exercise.Level? = nil
    ) -> [Exercise] {
        let tokens = CatalogEntry.searchKey(query ?? "").split(whereSeparator: \.isWhitespace)

        return catalog.filter { entry in
            if let muscleGroup, entry.muscleGroup != muscleGroup { return false }
            if let equipment, entry.equipmentKind != equipment { return false }
            if let category, entry.exercise.category != category { return false }
            if let level, entry.exercise.level != level { return false }
            return tokens.allSatisfy { token in entry.searchFields.contains { $0.contains(token) } }
        }
        .map(\.exercise)
    }
}

/// One catalog row with the keys `filter` matches on. `searchFields` are
/// the normalised name (also with its spaces removed), raw muscle
/// strings, raw equipment string and the classified equipment name.
private struct CatalogEntry {
    let exercise: Exercise
    let muscleGroup: MuscleGroup
    let equipmentKind: EquipmentKind
    let searchFields: [String]

    init(_ exercise: Exercise) {
        let kind = exercise.equipmentKind
        self.exercise = exercise
        muscleGroup = exercise.muscleGroup
        equipmentKind = kind
        var fields = [exercise.name] + exercise.primaryMuscles + exercise.secondaryMuscles
        if let equipment = exercise.equipment { fields.append(equipment) }
        fields.append(kind.displayName)
        let keys = fields.map(Self.searchKey)
        searchFields = keys + [keys[0].replacingOccurrences(of: " ", with: "")]
    }

    /// Folds case and diacritics and reads hyphens as spaces, so query
    /// and fields compare on the same terms.
    static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: " ")
    }
}
