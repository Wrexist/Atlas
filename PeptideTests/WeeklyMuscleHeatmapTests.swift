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

    func test_regions_singleMuscle_resolvesToExpectedRegion() {
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "chest"), [.chest])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "abdominals"), [.abdominals])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "lats"), [.lats])
    }

    func test_regions_pairedMuscle_resolvesToBothSides() {
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "biceps"),
                       [.bicepsLeft, .bicepsRight])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "quadriceps"),
                       [.quadricepsLeft, .quadricepsRight])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "glutes"),
                       [.glutesLeft, .glutesRight])
    }

    func test_regions_shoulders_lightUpFrontAndBack() {
        XCTAssertEqual(
            AnatomicalMuscle.regions(forRawMuscle: "shoulders"),
            [.shouldersFront, .shouldersBack]
        )
    }

    func test_regions_unknownMuscle_returnsEmpty() {
        XCTAssertTrue(AnatomicalMuscle.regions(forRawMuscle: "tendons").isEmpty)
    }

    func test_regions_isCaseInsensitive() {
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "CHEST"), [.chest])
        XCTAssertEqual(AnatomicalMuscle.regions(forRawMuscle: "Lats"),  [.lats])
    }

    func test_regions_forRawMuscles_unionsRegions() {
        let union = AnatomicalMuscle.regions(forRawMuscles: ["chest", "biceps"])
        XCTAssertEqual(union, [.chest, .bicepsLeft, .bicepsRight])
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

    func test_frequencies_sessionInsideWindow_contributesToPrimary() {
        // Bench Press primary muscle in the dataset: chest.
        let s = session(daysAgo: 2, exerciseID: "Barbell_Bench_Press", workingSets: 4)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertEqual(freqs[.chest], 4,
                       "Each working set on bench should contribute 1 point to chest")
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
        XCTAssertEqual(freqs[.chest], 3,
                       "Only working (non-warmup, completed) sets count")
    }

    func test_frequencies_secondaryMusclesGetHalfWeight() {
        // Bench Press: secondary muscles include triceps + shoulders.
        let s = session(daysAgo: 1, exerciseID: "Barbell_Bench_Press", workingSets: 4)
        let freqs = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        XCTAssertEqual(freqs[.tricepsLeft], 2)
        XCTAssertEqual(freqs[.tricepsRight], 2)
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
        // All sets unchecked — realistic for an in-progress session
        // the user abandoned. Should contribute zero.
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
            .chest: 5, .quadricepsLeft: 9, .lats: 3
        ]
        let top = WeeklyMuscleHeatmap.topMuscles(from: freqs, limit: 3)
        XCTAssertEqual(top.map(\.muscle), [.quadricepsLeft, .chest, .lats])
    }

    func test_topMuscles_tieBreaksAlphabetically() {
        let freqs: [AnatomicalMuscle: Double] = [
            .chest: 4, .lats: 4, .abdominals: 4
        ]
        let top = WeeklyMuscleHeatmap.topMuscles(from: freqs)
        // Stable order: alphabetical by raw value when tied.
        XCTAssertEqual(top.map(\.muscle), [.abdominals, .chest, .lats])
    }

    func test_topMuscles_respectsLimit() {
        let freqs: [AnatomicalMuscle: Double] = [
            .chest: 1, .lats: 2, .abdominals: 3, .glutesLeft: 4
        ]
        XCTAssertEqual(WeeklyMuscleHeatmap.topMuscles(from: freqs, limit: 2).count, 2)
    }
}

@MainActor
final class MuscleMapHighlightBuilderTests: XCTestCase {

    func test_highlights_primaryWinsOverSecondary_whenMuscleAppearsInBoth() {
        // Edge case: dataset listing the same muscle as both primary
        // and secondary. Primary should dominate so the user sees
        // the strong tint.
        let map = MuscleMapView.highlights(
            primaryRawMuscles: ["chest"],
            secondaryRawMuscles: ["chest", "triceps"]
        )
        XCTAssertEqual(map[.chest], .primary)
        XCTAssertEqual(map[.tricepsLeft], .secondary)
        XCTAssertEqual(map[.tricepsRight], .secondary)
    }

    func test_highlights_emptyInputReturnsEmptyMap() {
        XCTAssertTrue(MuscleMapView.highlights(
            primaryRawMuscles: [],
            secondaryRawMuscles: []
        ).isEmpty)
    }

    func test_intensityHighlights_normalisesAgainstMax() {
        let map = MuscleMapView.intensityHighlights(from: [
            .chest: 10,
            .lats: 5,
            .glutesLeft: 2.5,
        ])
        guard case .intensity(let chest)  = map[.chest] else { return XCTFail() }
        guard case .intensity(let lats)   = map[.lats] else { return XCTFail() }
        guard case .intensity(let glutes) = map[.glutesLeft] else { return XCTFail() }
        XCTAssertEqual(chest, 1.0, accuracy: 0.0001)
        XCTAssertEqual(lats, 0.5, accuracy: 0.0001)
        XCTAssertEqual(glutes, 0.25, accuracy: 0.0001)
    }

    func test_intensityHighlights_zeroOrEmpty_returnsEmpty() {
        XCTAssertTrue(MuscleMapView.intensityHighlights(from: [:]).isEmpty)
        XCTAssertTrue(MuscleMapView.intensityHighlights(from: [.chest: 0]).isEmpty)
    }
}
