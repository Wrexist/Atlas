import XCTest
@testable import Peptide

final class WorkoutSessionTests: XCTestCase {

    // MARK: - SetEntry math

    func test_setEntry_volume_isWeightTimesReps_whenCompleted() {
        let set = SetEntry(index: 1, weightKg: 100, reps: 5, completed: true)
        XCTAssertEqual(set.volumeKg, 500)
    }

    func test_setEntry_volume_isZero_whenIncomplete() {
        let set = SetEntry(index: 1, weightKg: 100, reps: 5, completed: false)
        XCTAssertEqual(set.volumeKg, 0,
                       "Incomplete sets should not contribute to working volume")
    }

    func test_setEntry_volume_isZero_forWarmupSets() {
        let set = SetEntry(index: 1, weightKg: 60, reps: 8,
                           completed: true, isWarmup: true)
        XCTAssertEqual(set.volumeKg, 0,
                       "Warm-up sets should not contribute to working volume")
    }

    func test_setEntry_estimatedOneRepMax_singleRep_returnsExactWeight() {
        let set = SetEntry(index: 1, weightKg: 140, reps: 1, completed: true)
        XCTAssertEqual(set.estimatedOneRepMaxKg ?? 0, 140, accuracy: 0.0001)
    }

    func test_setEntry_estimatedOneRepMax_followsEpleyFormula() {
        // Epley: 1RM ≈ w * (1 + r/30). 100kg × 5 → 100 × (1 + 5/30) = 116.66…
        let set = SetEntry(index: 1, weightKg: 100, reps: 5, completed: true)
        let expected = 100.0 * (1.0 + 5.0 / 30.0)
        XCTAssertEqual(set.estimatedOneRepMaxKg ?? 0, expected, accuracy: 0.0001)
    }

    func test_setEntry_estimatedOneRepMax_nilForWarmupOrIncomplete() {
        let warmup = SetEntry(index: 1, weightKg: 60, reps: 8,
                              completed: true, isWarmup: true)
        XCTAssertNil(warmup.estimatedOneRepMaxKg)

        let incomplete = SetEntry(index: 1, weightKg: 100, reps: 5, completed: false)
        XCTAssertNil(incomplete.estimatedOneRepMaxKg)
    }

    func test_setEntry_estimatedOneRepMax_nilForZeroReps() {
        let set = SetEntry(index: 1, weightKg: 100, reps: 0, completed: true)
        XCTAssertNil(set.estimatedOneRepMaxKg)
    }

    // MARK: - WorkoutSession aggregation

    private func makeSession(sets: [SetEntry], startedAt: Date = Date(),
                             finishedAt: Date? = nil) -> WorkoutSession {
        let exercise = WorkoutExerciseEntry(
            exerciseID: "Bench_Press", index: 0, sets: sets
        )
        return WorkoutSession(
            startedAt: startedAt,
            finishedAt: finishedAt,
            exercises: [exercise]
        )
    }

    func test_session_totalVolume_sumsOnlyCompletedWorkingSets() {
        let session = makeSession(sets: [
            SetEntry(index: 1, weightKg: 60, reps: 10, completed: true, isWarmup: true), // skip
            SetEntry(index: 2, weightKg: 80, reps: 8, completed: true),                  // 640
            SetEntry(index: 3, weightKg: 80, reps: 8, completed: true),                  // 640
            SetEntry(index: 4, weightKg: 80, reps: 8, completed: false),                 // skip
        ])
        XCTAssertEqual(session.totalVolumeKg, 1280)
    }

    func test_session_completedSetCount_excludesWarmupsAndIncomplete() {
        let session = makeSession(sets: [
            SetEntry(index: 1, weightKg: 60, reps: 10, completed: true, isWarmup: true),
            SetEntry(index: 2, weightKg: 80, reps: 8, completed: true),
            SetEntry(index: 3, weightKg: 80, reps: 8, completed: true),
            SetEntry(index: 4, weightKg: 80, reps: 8, completed: false),
        ])
        XCTAssertEqual(session.completedSetCount, 2)
    }

    func test_session_isActive_whenFinishedAtIsNil() {
        let active = makeSession(sets: [], finishedAt: nil)
        XCTAssertTrue(active.isActive)

        let finished = makeSession(sets: [], finishedAt: Date())
        XCTAssertFalse(finished.isActive)
    }

    func test_session_elapsedSeconds_clampsToZeroForFutureStart() {
        let now = Date()
        let future = makeSession(sets: [], startedAt: now.addingTimeInterval(60))
        XCTAssertEqual(future.elapsedSeconds(now: now), 0,
                       "Negative elapsed (clock skew, time-travel debug) should clamp to 0")
    }

    func test_session_elapsedSeconds_computesAgainstFinishedAtWhenSet() {
        let started = Date(timeIntervalSince1970: 1_000_000)
        let finished = started.addingTimeInterval(1800) // 30 min
        let session = makeSession(sets: [],
                                  startedAt: started, finishedAt: finished)
        XCTAssertEqual(session.elapsedSeconds(now: Date()), 1800,
                       "Finished sessions should not extend their elapsed time past finishedAt")
    }

    // MARK: - WorkoutExerciseEntry

    func test_exerciseEntry_topEstimatedOneRepMax_pickHighestValid() {
        let entry = WorkoutExerciseEntry(
            exerciseID: "Squat",
            index: 0,
            sets: [
                SetEntry(index: 1, weightKg: 100, reps: 8, completed: true),
                SetEntry(index: 2, weightKg: 110, reps: 5, completed: true),
                SetEntry(index: 3, weightKg: 120, reps: 3, completed: true),
                SetEntry(index: 4, weightKg: 130, reps: 1, completed: true),
                SetEntry(index: 5, weightKg: 60, reps: 10, completed: true, isWarmup: true),
            ]
        )
        // Highest e1RM among the working sets:
        //   100 × 1+8/30 ≈ 126.66
        //   110 × 1+5/30 ≈ 128.33
        //   120 × 1+3/30 = 132.00
        //   130 × 1     = 130.00
        // → 132.00 from set 3.
        let expected = 120.0 * (1.0 + 3.0 / 30.0)
        XCTAssertEqual(entry.topEstimatedOneRepMaxKg ?? 0, expected, accuracy: 0.0001)
    }
}
