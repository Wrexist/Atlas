import XCTest
@testable import Peptide

@MainActor
final class ExerciseLibraryTests: XCTestCase {

    /// `ExerciseLibrary` is a singleton; load it once for the suite.
    /// Idempotent — calling `load()` after a successful parse is a
    /// no-op.
    private var library: ExerciseLibrary {
        let lib = ExerciseLibrary.shared
        lib.load()
        return lib
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

    func test_load_isIdempotent() {
        let firstCount = library.bundled.count
        library.load()
        XCTAssertEqual(library.bundled.count, firstCount,
                       "load() should be a no-op on the second call")
    }

    func test_load_everyExercise_hasNonEmptyName() {
        for exercise in library.bundled {
            XCTAssertFalse(exercise.name.isEmpty, "Exercise \(exercise.id) has empty name")
        }
    }

    func test_load_everyExercise_hasInstructions() {
        let withoutInstructions = library.bundled.filter { $0.instructions.isEmpty }
        XCTAssertTrue(withoutInstructions.isEmpty,
                      "Found \(withoutInstructions.count) exercises with no instructions: \(withoutInstructions.prefix(3).map(\.id))")
    }

    // MARK: - Lookup

    func test_lookup_byBundledID_returnsMatch() {
        // The dataset's first exercise is "3/4 Sit-Up" (id "3_4_Sit-Up").
        // Use an id we know is stable across dataset releases.
        let id = "3_4_Sit-Up"
        let hit = library.lookup(id: id)
        XCTAssertNotNil(hit, "Stable bundled id \(id) should resolve")
        XCTAssertEqual(hit?.name, "3/4 Sit-Up")
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
    }

    // MARK: - Filter

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

    func test_filter_bodyweightEquipment_includesBodyOnlyAndNoneRaw() {
        // The dataset uses both "body only" and (rarely) "none" / nil
        // — our taxonomy collapses both to `.bodyweight`. Make sure
        // the filter picks both up.
        let bodyweight = library.filter(equipment: .bodyweight)
        XCTAssertFalse(bodyweight.isEmpty)
        for exercise in bodyweight {
            let raw = exercise.equipment?.lowercased() ?? ""
            XCTAssertTrue(
                raw.isEmpty || raw == "body only" || raw == "none" || raw == "bodyweight",
                "Bodyweight filter included \(exercise.name) with raw equipment \(raw)"
            )
        }
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

    // MARK: - Equipment-access scoping

    func test_availableForEquipment_emptySetReturnsAll() {
        let all = library.availableForEquipment([])
        XCTAssertEqual(all.count, library.bundled.count + library.custom.count,
                       "An empty access set should fall through to the full union of bundled + custom")
    }

    func test_availableForEquipment_filtersToSubset() {
        let scoped = library.availableForEquipment([.barbell])
        XCTAssertFalse(scoped.isEmpty)
        for exercise in scoped {
            XCTAssertEqual(exercise.equipmentKind, .barbell)
        }
    }
}
