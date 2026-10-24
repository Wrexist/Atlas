import XCTest
@testable import Peptide

@MainActor
final class ExerciseLibraryTests: XCTestCase {

    /// `ExerciseLibrary` is a singleton — `setUp` awaits the bundled
    /// load once for the suite. Idempotent — calling `load()` after a
    /// successful parse is a no-op.
    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    /// The shared singleton's `custom` overlay survives across tests
    /// because XCTest re-uses the same process. Wipe between cases
    /// so an attach-and-don't-clean-up in one test can't leak into
    /// the next.
    override func tearDown() {
        ExerciseLibrary.shared.attachCustomExercises([])
        super.tearDown()
    }

    // MARK: - Bundled load

    func test_load_decodesBundledDataset() {
        XCTAssertFalse(library.bundled.isEmpty,
                       "Bundled exercises.json failed to decode — check the resource is in the app bundle")
        XCTAssertGreaterThan(library.bundled.count, 500,
                             "Bundled dataset should contain the full yuhonas/free-exercise-db catalog (~870 entries)")
    }

    func test_load_isIdempotent() async {
        let firstCount = library.bundled.count
        await library.load()
        XCTAssertEqual(library.bundled.count, firstCount,
                       "load() should be a no-op on the second call")
    }

    func test_load_everyExercise_hasNonEmptyName() {
        for exercise in library.bundled {
            XCTAssertFalse(exercise.name.isEmpty, "Exercise \(exercise.id) has empty name")
        }
    }

    func test_load_everyExercise_hasInstructions() {
        let missing = library.bundled.filter(\.instructions.isEmpty).map(\.id)
        XCTAssertTrue(missing.isEmpty, "Exercises with no instructions: \(missing.sorted())")
    }

    /// Swedish ships every step of every exercise. A step count that drifts
    /// from the English means a step was merged, split or lost in
    /// translation, so the numbered list would no longer line up.
    func test_swedishInstructions_coverEveryExerciseStepForStep() {
        let swedish = ExerciseLibrary.translatedSteps(language: "sv")
        for exercise in library.bundled {
            guard let steps = swedish[exercise.id] else {
                XCTFail("No Swedish instructions for \(exercise.id)")
                continue
            }
            XCTAssertEqual(steps.count, exercise.instructions.count,
                           "Swedish step count differs for \(exercise.id)")
            XCTAssertFalse(steps.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
                           "Empty Swedish step in \(exercise.id)")
        }
    }

    /// The steps follow the locale the view hands in (the in-app language
    /// picker), not the device language.
    func test_steps_followTheGivenLocale() throws {
        let squat = try XCTUnwrap(library.lookup(id: "Barbell_Squat"))
        let swedish = ExerciseLibrary.translatedSteps(language: "sv")["Barbell_Squat"]
        XCTAssertEqual(library.steps(for: squat, locale: Locale(identifier: "sv_SE")), swedish)
        XCTAssertEqual(library.steps(for: squat, locale: Locale(identifier: "en_US")), squat.instructions)
    }

    func test_translatedSteps_withoutFile_isEmpty() {
        XCTAssertTrue(ExerciseLibrary.translatedSteps(language: "en").isEmpty)
    }

    // MARK: - Lookup

    func test_lookup_byBundledID_returnsMatch() {
        // The dataset's first exercise is "3/4 Sit-Up" (id "3_4_Sit-Up").
        // Use an id we know is stable across dataset releases.
        let id = "3_4_Sit-Up"
        let hit = library.lookup(id: id)
        XCTAssertNotNil(hit, "Stable bundled id \(id) should resolve")
        XCTAssertEqual(hit?.name, "3/4 Sit-Up")
        XCTAssertEqual(hit?.isCustom, false)
    }

    func test_lookup_byUnknownID_returnsNil() {
        XCTAssertNil(library.lookup(id: "definitely_not_a_real_exercise_id_123"))
    }

    func test_lookup_byCustomExerciseID_returnsLifted() {
        let custom = CustomExercise(name: "Test Curl", primaryMuscles: ["biceps"])
        library.attachCustomExercises([custom])
        defer { library.attachCustomExercises([]) }

        let hit = library.lookup(id: custom.id)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.name, "Test Curl")
        XCTAssertEqual(hit?.primaryMuscles, ["biceps"])
        XCTAssertEqual(hit?.isCustom, true)
    }

    func test_displayName_unknownID_readsUnknownExerciseNotTheRawID() {
        XCTAssertEqual(library.displayName(for: "custom_deleted_123"), "Unknown exercise")
    }

    // MARK: - Custom exercises from SwiftData

    /// A relaunch starts with an empty overlay; `load()` must read the
    /// stored custom exercises itself rather than wait for a recap.
    func test_load_afterRelaunch_includesStoredCustomExercises() async {
        let repo = SwiftDataRepository.shared
        repo.configureForTesting()
        let custom = CustomExercise(name: "Zqx Landmine Row", primaryMuscles: ["lats"], equipment: "barbell")
        repo.upsertCustomExercise(custom)
        defer { repo.deleteCustomExercise(id: custom.id) }
        library.attachCustomExercises([])
        library.reset()

        await library.load()

        XCTAssertEqual(library.lookup(id: custom.id)?.name, "Zqx Landmine Row")
        XCTAssertEqual(library.filter(query: "zqx").map(\.id), [custom.id])
    }

    func test_reloadCustomExercises_dropsRowsDeletedFromTheStore() async {
        let repo = SwiftDataRepository.shared
        repo.configureForTesting()
        let custom = CustomExercise(name: "Zqx Cable Fly", primaryMuscles: ["chest"], equipment: "cable")
        repo.upsertCustomExercise(custom)
        library.reloadCustomExercises()
        XCTAssertNotNil(library.lookup(id: custom.id))

        repo.deleteCustomExercise(id: custom.id)
        library.reloadCustomExercises()

        XCTAssertNil(library.lookup(id: custom.id))
    }


    func test_filter_afterAttachingCustom_includesItSortedByName() {
        let custom = CustomExercise(name: "Aaa Test Curl", primaryMuscles: ["biceps"])
        library.attachCustomExercises([custom])
        defer { library.attachCustomExercises([]) }

        let results = library.filter(query: "aaa test")
        XCTAssertEqual(results.map(\.id), [custom.id])
        let names = library.filter().map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func test_filter_byMuscleGroup_returnsOnlyMatches() {
        let chestOnly = library.filter(muscleGroup: .chest)
        XCTAssertFalse(chestOnly.isEmpty, "Expected chest exercises to exist in dataset")
        for exercise in chestOnly {
            XCTAssertEqual(exercise.muscleGroup, .chest,
                           "Exercise \(exercise.id) returned by chest filter but its group is \(exercise.muscleGroup)")
        }
    }

    func test_filter_byEquipment_returnsOnlyMatches() {
        let dumbbellOnly = library.filter(equipment: .dumbbell)
        XCTAssertFalse(dumbbellOnly.isEmpty)
        for exercise in dumbbellOnly {
            XCTAssertEqual(exercise.equipmentKind, .dumbbell)
        }
    }

    func test_filter_bodyweightEquipment_includesBodyOnlyNoneAndUntaggedHangs() {
        // The dataset uses "body only", nil, and "other" for pull-ups,
        // dips and stretches that need no load — all read as bodyweight.
        // Nothing tagged with real kit (barbell, cable…) may leak in.
        let bodyweight = library.filter(equipment: .bodyweight)
        XCTAssertFalse(bodyweight.isEmpty)
        for exercise in bodyweight {
            let raw = exercise.equipment?.lowercased() ?? ""
            XCTAssertTrue(
                ["", "body only", "none", "bodyweight", "other"].contains(raw),
                "Bodyweight filter included \(exercise.name) with raw equipment \(raw)"
            )
        }
        XCTAssertTrue(bodyweight.contains { $0.id == "Mixed_Grip_Chin" })
    }

    func test_filter_byQuery_matchesNameSubstring() {
        let benches = library.filter(query: "bench")
        XCTAssertFalse(benches.isEmpty)
        XCTAssertTrue(
            benches.contains(where: { $0.name.lowercased().contains("bench") }),
            "Query 'bench' should match at least one named bench exercise"
        )
    }

    func test_filter_byQuery_matchesMuscleString() {
        let triceps = library.filter(query: "triceps")
        XCTAssertFalse(triceps.isEmpty)
        // Every match should have triceps mentioned somewhere searchable.
        for exercise in triceps.prefix(5) {
            let bag = ([exercise.name] + exercise.primaryMuscles + exercise.secondaryMuscles)
                .map { $0.lowercased() }
                .joined(separator: " ")
            XCTAssertTrue(bag.contains("triceps"))
        }
    }

    func test_filter_byQuery_isCaseInsensitive() {
        let lower = library.filter(query: "squat")
        let upper = library.filter(query: "SQUAT")
        XCTAssertEqual(lower.count, upper.count,
                       "Query matching should be case-insensitive")
    }

    func test_filter_multiWordQueryInAnyOrder_matchesEveryWord() {
        let ordered = library.filter(query: "dumbbell bench press").map(\.id)
        let shuffled = library.filter(query: "bench press dumbbell").map(\.id)
        XCTAssertTrue(ordered.contains("Dumbbell_Bench_Press"))
        XCTAssertEqual(ordered, shuffled)
    }

    func test_filter_hyphenSpaceAndJoinedSpellings_matchSameExercise() {
        for query in ["pull-up", "pull up", "pullup"] {
            XCTAssertTrue(
                library.filter(query: query).contains { $0.id == "Band_Assisted_Pull-Up" },
                "Query '\(query)' should match Band Assisted Pull-Up"
            )
        }
    }

    func test_filter_combined_appliesAllPredicates() {
        let pushups = library.filter(query: "push", equipment: .bodyweight)
        XCTAssertFalse(pushups.isEmpty)
        for exercise in pushups {
            XCTAssertEqual(exercise.equipmentKind, .bodyweight)
            let bag = ([exercise.name] + exercise.primaryMuscles + exercise.secondaryMuscles)
                .map { $0.lowercased() }
                .joined(separator: " ")
            XCTAssertTrue(bag.contains("push"))
        }
    }

    func test_filter_byCategory_returnsOnlyMatches() {
        let stretches = library.filter(category: .stretching)
        XCTAssertFalse(stretches.isEmpty)
        for s in stretches { XCTAssertEqual(s.category, .stretching) }
    }
}
