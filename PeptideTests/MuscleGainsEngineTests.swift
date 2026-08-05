import XCTest
@testable import Peptide

@MainActor
final class MuscleGainsEngineTests: XCTestCase {

    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    override func tearDown() {
        ExerciseLibrary.shared.attachCustomExercises([])
        super.tearDown()
    }

    private func session(daysAgo: Double, exerciseID: String,
                         workingSets: Int) -> WorkoutSession {
        let started = Date().addingTimeInterval(-daysAgo * 86_400)
        var sets: [SetEntry] = []
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

    // MARK: - totalFrequencies

    func test_totalFrequencies_includesSessionsOutsideWeeklyWindow() {
        let old = session(daysAgo: 100, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 4)
        let recent = session(daysAgo: 1, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 3)
        let totals = MuscleGainsEngine.totalFrequencies(from: [old, recent], library: library)
        XCTAssertEqual(totals[.pecSternal], 7,
                       "All-time totals should accumulate across the entire history")
    }

    func test_totalFrequencies_matchesWeeklyWeighting() {
        // Same session must produce identical per-head stimulus in both
        // aggregations — they share stimulusHeads.
        let s = session(daysAgo: 1, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 4)
        let weekly = WeeklyMuscleHeatmap.frequencies(from: [s], library: library)
        let totals = MuscleGainsEngine.totalFrequencies(from: [s], library: library)
        XCTAssertEqual(weekly, totals)
    }

    func test_totalFrequencies_emptyHistoryReturnsEmpty() {
        XCTAssertTrue(MuscleGainsEngine.totalFrequencies(from: [], library: library).isEmpty)
    }

    // MARK: - weeklyRegularity

    func test_weeklyRegularity_countsDistinctWeeksOverWindow() throws {
        // Bench in four distinct calendar weeks (each pair 7 days apart)
        // → sternal pec trained 4 of the last 12 weeks.
        let sessions = [1.0, 8.0, 15.0, 22.0].map {
            session(daysAgo: $0, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 3)
        }
        let regularity = MuscleGainsEngine.weeklyRegularity(from: sessions, library: library)
        XCTAssertEqual(try XCTUnwrap(regularity[.pecSternal]), 4.0 / 12.0, accuracy: 0.0001)
    }

    func test_weeklyRegularity_sameWeekSessionsCountOnce() throws {
        let sessions = [
            session(daysAgo: 0.01, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 3),
            session(daysAgo: 0.02, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 3),
        ]
        let regularity = MuscleGainsEngine.weeklyRegularity(from: sessions, library: library)
        XCTAssertEqual(try XCTUnwrap(regularity[.pecSternal]), 1.0 / 12.0, accuracy: 0.0001,
                       "Two sessions in the same week are one trained week, not two")
    }

    func test_weeklyRegularity_excludesSessionsOlderThanWindow() {
        let s = session(daysAgo: 100, exerciseID: "Barbell_Bench_Press_-_Medium_Grip", workingSets: 3)
        let regularity = MuscleGainsEngine.weeklyRegularity(from: [s], library: library)
        XCTAssertTrue(regularity.isEmpty,
                      "Sessions before the 12-week window should not count")
    }
}
