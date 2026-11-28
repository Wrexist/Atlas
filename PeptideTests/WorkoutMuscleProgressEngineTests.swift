import XCTest
@testable import Peptide

@MainActor
final class WorkoutMuscleProgressEngineTests: XCTestCase {

    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    private func progress(_ session: WorkoutSession) -> WorkoutMuscleProgressEngine.Progress {
        WorkoutMuscleProgressEngine.progress(of: session) { self.library.lookup(id: $0) }
    }

    private func entry(_ id: String, index: Int, done: Int, planned: Int, warmups: Int = 0) -> WorkoutExerciseEntry {
        let warm = (0..<warmups).map { SetEntry(index: $0 + 1, weightKg: 10, reps: 10, completed: true, isWarmup: true) }
        let working = (0..<planned).map {
            SetEntry(index: warmups + $0 + 1, weightKg: 20, reps: 10, completed: $0 < done)
        }
        return WorkoutExerciseEntry(exerciseID: id, index: index, sets: warm + working)
    }

    func test_progress_warmupsNeverCountTowardDoneOrPlanned() {
        let result = progress(WorkoutSession(exercises: [
            entry("Incline_Dumbbell_Press", index: 0, done: 1, planned: 3, warmups: 2)
        ]))

        XCTAssertEqual(result.doneSets, 1)
        XCTAssertEqual(result.plannedSets, 3)
        XCTAssertEqual(result.fraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(result.rows.first { $0.target == .chest }?.done, 1)
        XCTAssertEqual(result.rows.first { $0.target == .chest }?.planned, 3)
    }

    func test_progress_rowsFollowWorkoutOrderAndSumSameMuscle() {
        let result = progress(WorkoutSession(exercises: [
            entry("Barbell_Full_Squat", index: 0, done: 3, planned: 3),
            entry("Dumbbell_Bicep_Curl", index: 1, done: 1, planned: 3),
            entry("Hammer_Curls", index: 2, done: 2, planned: 2),
        ]))

        XCTAssertEqual(result.rows.map(\.target), [.quads, .biceps])
        let biceps = result.rows.first { $0.target == .biceps }
        XCTAssertEqual(biceps?.done, 3)
        XCTAssertEqual(biceps?.planned, 5)
        XCTAssertEqual(biceps?.isComplete, false)
        XCTAssertEqual(result.rows.first { $0.target == .quads }?.isComplete, true)
        XCTAssertEqual(result.maxDone, 3)
    }

    func test_progress_secondaryMusclesGetNoRow() {
        let result = progress(WorkoutSession(exercises: [
            entry("Incline_Dumbbell_Press", index: 0, done: 2, planned: 3)
        ]))

        XCTAssertFalse(result.rows.contains { $0.target == .triceps })
    }

    func test_progress_unknownExerciseCountsInTotalsWithoutRow() {
        let result = progress(WorkoutSession(exercises: [
            entry("Not_A_Real_Exercise", index: 0, done: 2, planned: 4)
        ]))

        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.doneSets, 2)
        XCTAssertEqual(result.plannedSets, 4)
    }

    func test_progress_emptyWorkout_isZeroPercent() {
        let result = progress(WorkoutSession(exercises: []))

        XCTAssertEqual(result.fraction, 0)
        XCTAssertEqual(result.maxDone, 0)
        XCTAssertTrue(result.rows.isEmpty)
    }

    func test_frequencies_onlyCompletedWorkingSetsLightTheMap() {
        let untouched = WorkoutSession(exercises: [entry("Dumbbell_Bicep_Curl", index: 0, done: 0, planned: 3)])
        XCTAssertTrue(WorkoutMuscleProgressEngine.frequencies(of: untouched, library: library).isEmpty)

        let started = WorkoutSession(exercises: [entry("Dumbbell_Bicep_Curl", index: 0, done: 2, planned: 3)])
        XCTAssertGreaterThan(WorkoutMuscleProgressEngine.frequencies(of: started, library: library)[.biceps] ?? 0, 0)
    }
}
