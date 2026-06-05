import XCTest
@testable import Peptide

@MainActor
final class WeeklyMuscleHeatmapTests: XCTestCase {

    private var library: ExerciseLibrary {
        let lib = ExerciseLibrary.shared
        lib.load()
        return lib
    }

    override func tearDown() {
        ExerciseLibrary.shared.attachCustomExercises([])
        super.tearDown()
    }

    // MARK: - AnatomicalMuscle.regions(forRawMuscle:)

    func test_regions_singleMuscle_resolvesToExpectedHeads() {
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "chest"),
                       [.pecSternal, .pecClavicular])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "abdominals"), [.abdominals])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "lats"), [.lats])
    }

    func test_regions_multiHeadMuscle_resolvesToAllHeads() {
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "biceps"), [.biceps])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "quadriceps"),
                       [.quadRectus, .quadLateralis, .quadMedialis])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "glutes"), [.glutes])
    }

    func test_regions_shoulders_lightUpEveryDeltoidHead() {
        XCTAssertEqual(
            AnatomicalMuscle.regions(forRawMuscle: "shoulders"),
            [.deltAnterior, .deltLateralFront, .deltLateralBack, .deltPosterior]
        )
    }

    func test_regions_unknownMuscle_returnsEmpty() {
        XCTAssertTrue(AnatomicalMuscle.regions(forRawMuscle: "tendons").isEmpty)
    }

    func test_regions_isCaseInsensitive() {
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "CHEST"),
                       [.pecSternal, .pecClavicular])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "Lats"), [.lats])
    }

    func test_regions_forRawMuscles_unionsRegions() {
        let union = AnatomicalMuscle.regions(forRawMuscles: ["chest", "biceps"])
        XCTAssertEqual(union, [.pecSternal, .pecClavicular, .biceps])
    }

    // MARK: - AnatomicalMuscle.headWeights (per-head emphasis)

    func test_headWeights_chest_inclineFavoursClavicular() {
        let incline = AnatomicalMuscle.headWeights(forRawMuscle: "chest",
                                                   exerciseName: "Incline Dumbbell Press")
        XCTAssertEqual(incline[.pecClavicular], 1.0)
        XCTAssertEqual(incline[.pecSternal], 0.55)
    }

    func test_headWeights_chest_flatFavoursSternal() {
        let flat = AnatomicalMuscle.headWeights(forRawMuscle: "chest",
                                                exerciseName: "Barbell Bench Press")
        XCTAssertEqual(flat[.pecSternal], 1.0)
        XCTAssertEqual(flat[.pecClavicular], 0.70)
    }

    func test_headWeights_triceps_pushdownVsOverhead() {
        let pushdown = AnatomicalMuscle.headWeights(forRawMuscle: "triceps",
                                                    exerciseName: "Cable Triceps Pushdown")
        XCTAssertEqual(pushdown[.tricepsLateral], 1.0)
        XCTAssertEqual(pushdown[.tricepsLong], 0.60)

        let overhead = AnatomicalMuscle.headWeights(forRawMuscle: "triceps",
                                                    exerciseName: "Overhead Triceps Extension")
        XCTAssertEqual(overhead[.tricepsLong], 1.0)
        XCTAssertEqual(overhead[.tricepsLateral], 0.60)
    }

    func test_headWeights_calves_seatedFavoursSoleus() {
        let seated = AnatomicalMuscle.headWeights(forRawMuscle: "calves",
                                                  exerciseName: "Seated Calf Raise")
        XCTAssertEqual(seated[.soleus], 1.0)
        XCTAssertEqual(seated[.gastrocnemius], 0.40)

        let standing = AnatomicalMuscle.headWeights(forRawMuscle: "calves",
                                                    exerciseName: "Standing Calf Raise")
        XCTAssertEqual(standing[.gastrocnemius], 1.0)
    }

    func test_headWeights_unknownRaw_isEmpty() {
        XCTAssertTrue(AnatomicalMuscle.headWeights(forRawMuscle: "tendons").isEmpty)
    }

    // MARK: - WeeklyMuscleHeatmap.frequencies

    private func session(daysAgo: Double, exerciseID: String,
                         workingSets: Int, warmupSets: Int = 0) -> WorkoutSession {
        let started = Date().addingTimeInterval(-daysAgo * 86_400)
        var sets: [SetEntry] = []
        for _ in 0..<warmupSets {
            sets.append(SetEntry(index: sets.count + 1, weightKg: 40, reps: 10,
                                 completed: true, isWarmup: true))
        }
        for _ in 0..<workingSets {
            sets.append(SetEntry(index: sets.count + 1, weightKg: 80, reps: 8,
                                 completed: true))
        }
        return WorkoutSession(
            startedAt: started,
            finishedAt: started.addingTimeInterval(3600),
            exercises: [
                WorkoutExerciseEntry(exerciseID: exerciseID, index: 0, sets: sets)
            ]
        )
    }

    func test_frequencies_sessionInsideWindow_contributesToPrimaryHead() {
        // Flat bench press: chest primary → sternal head at full weight.
        let s = session(daysAgo: 2, exerciseID: "Barbell_Bench_Press", workingSets: 4)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertEqual(freqs[.pecSternal], 4,
                       "Each working set on flat bench should fully light the sternal pec")
    }

    func test_frequencies_sessionOutsideWindow_isExcluded() {
        let s = session(daysAgo: 14, exerciseID: "Barbell_Bench_Press", workingSets: 4)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertTrue(freqs.isEmpty,
                      "Sessions older than the window should not contribute")
    }

    func test_frequencies_warmupAndIncompleteSets_excluded() {
        let s = session(daysAgo: 1, exerciseID: "Barbell_Bench_Press",
                        workingSets: 3, warmupSets: 5)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertEqual(freqs[.pecSternal], 3,
                       "Only working (non-warmup, completed) sets count")
    }

    func test_frequencies_secondaryMusclesGetHalfWeight() {
        // Bench Press secondary muscles include triceps (default head
        // weight 0.85): 4 sets × 0.5 × 0.85 = 1.7 per triceps head.
        let s = session(daysAgo: 1, exerciseID: "Barbell_Bench_Press", workingSets: 4)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertEqual(freqs[.tricepsLong] ?? 0, 1.7, accuracy: 0.0001)
        XCTAssertEqual(freqs[.tricepsLateral] ?? 0, 1.7, accuracy: 0.0001)
    }

    func test_frequencies_emptySessionsListReturnsEmpty() {
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [], library: library)
        XCTAssertTrue(freqs.isEmpty)
    }

    func test_frequencies_unknownExerciseID_doesNotCrash() {
        let s = session(daysAgo: 1, exerciseID: "definitely_not_real",
                        workingSets: 4)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertTrue(freqs.isEmpty,
                      "Unknown exercise IDs should be skipped, not crash")
    }

    func test_frequencies_sessionWithNoCompletedSets_isExcluded() {
        let started = Date().addingTimeInterval(-86_400)
        let s = WorkoutSession(
            startedAt: started,
            finishedAt: nil,
            exercises: [
                WorkoutExerciseEntry(
                    exerciseID: "Barbell_Bench_Press",
                    index: 0,
                    sets: [
                        SetEntry(index: 1, weightKg: 80, reps: 8, completed: false),
                        SetEntry(index: 2, weightKg: 80, reps: 8, completed: false),
                    ]
                )
            ]
        )
        XCTAssertTrue(WeeklyMuscleHeatmap.frequencies(from: [s], library: library).isEmpty)
    }

    // MARK: - topMuscles

    func test_topMuscles_returnsDescendingByCount() {
        let freqs: [AnatomicalMuscle: Double] = [
            .pecSternal: 5, .quadRectus: 9, .lats: 3
        ]
        let top = WeeklyMuscleHeatmap.topMuscles(from: freqs, limit: 3)
        XCTAssertEqual(top.map(\.muscle), [.quadRectus, .pecSternal, .lats])
    }

    func test_topMuscles_tieBreaksAlphabetically() {
        let freqs: [AnatomicalMuscle: Double] = [
            .pecSternal: 4, .lats: 4, .abdominals: 4
        ]
        let top = WeeklyMuscleHeatmap.topMuscles(from: freqs)
        // Stable order: alphabetical by raw value when tied.
        XCTAssertEqual(top.map(\.muscle), [.abdominals, .lats, .pecSternal])
    }

    func test_topMuscles_respectsLimit() {
        let freqs: [AnatomicalMuscle: Double] = [
            .pecSternal: 1, .lats: 2, .abdominals: 3, .glutes: 4
        ]
        XCTAssertEqual(WeeklyMuscleHeatmap.topMuscles(from: freqs, limit: 2).count, 2)
    }
}

@MainActor
final class MuscleMapHighlightBuilderTests: XCTestCase {

    func test_highlights_primaryWinsOverSecondary_whenMuscleAppearsInBoth() {
        // Edge case: same muscle listed as both primary and secondary.
        // Primary should dominate so the user sees the strong tint.
        let map = MuscleMapView.highlights(
            primaryRawMuscles: ["chest"],
            secondaryRawMuscles: ["chest", "triceps"]
        )
        XCTAssertEqual(map[.pecSternal], .primary)
        XCTAssertEqual(map[.tricepsLong], .secondary)
        XCTAssertEqual(map[.tricepsLateral], .secondary)
    }

    func test_highlights_emptyInputReturnsEmptyMap() {
        XCTAssertTrue(MuscleMapView.highlights(
            primaryRawMuscles: [],
            secondaryRawMuscles: []
        ).isEmpty)
    }

    func test_intensityHighlights_normalisesAgainstMax() {
        let map = MuscleMapView.intensityHighlights(from: [
            .pecSternal: 10,
            .lats: 5,
            .glutes: 2.5,
        ])
        guard case .intensity(let chest)  = map[.pecSternal] else { return XCTFail() }
        guard case .intensity(let lats)   = map[.lats] else { return XCTFail() }
        guard case .intensity(let glutes) = map[.glutes] else { return XCTFail() }
        XCTAssertEqual(chest, 1.0, accuracy: 0.0001)
        XCTAssertEqual(lats, 0.5, accuracy: 0.0001)
        XCTAssertEqual(glutes, 0.25, accuracy: 0.0001)
    }

    func test_intensityHighlights_zeroOrEmpty_returnsEmpty() {
        XCTAssertTrue(MuscleMapView.intensityHighlights(from: [:]).isEmpty)
        XCTAssertTrue(MuscleMapView.intensityHighlights(from: [.pecSternal: 0]).isEmpty)
    }
}
