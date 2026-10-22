import XCTest
@testable import Peptide

/// Covers the PR detection engine's per-exercise upserts and the
/// bodyweight-reps track added to fix audit Train H3 (a session of
/// all-zero-weight bodyweight reps used to produce no PRs because
/// `bestE1RM > 0` and `bestAbs > 0` both failed for weightKg == 0).
///
/// The engine writes through `SwiftDataRepository.shared`, which is
/// a singleton with potentially live state. These tests scrub the
/// records for the test-only exerciseIDs they use, in both setUp
/// and tearDown, so they don't poison the user's real records when
/// run on a developer machine.
@MainActor
final class PRDetectionEngineTests: XCTestCase {

    private let testExerciseIDs: Set<String> = [
        "test_pushups", "test_bench", "test_squat", PRDetectionEngineTests.barbellBenchID,
    ]
    private static let barbellBenchID = "Barbell_Bench_Press_-_Medium_Grip"

    override func setUp() {
        super.setUp()
        scrubTestRecords()
    }

    override func tearDown() {
        scrubTestRecords()
        super.tearDown()
    }

    private func scrubTestRecords() {
        let repo = SwiftDataRepository.shared
        for id in testExerciseIDs {
            repo.deletePersonalRecord(exerciseID: id)
        }
    }

    // MARK: - Helpers

    private func session(
        exerciseID: String,
        sets: [SetEntry],
        finishedAt: Date = Date()
    ) -> WorkoutSession {
        WorkoutSession(
            startedAt: finishedAt.addingTimeInterval(-3600),
            finishedAt: finishedAt,
            exercises: [
                WorkoutExerciseEntry(
                    exerciseID: exerciseID,
                    index: 1,
                    sets: sets
                )
            ]
        )
    }

    private func completedSet(weightKg: Double, reps: Int) -> SetEntry {
        SetEntry(
            index: 1,
            weightKg: weightKg,
            reps: reps,
            completed: true,
            isWarmup: false,
            completedAt: Date()
        )
    }

    // MARK: - Bodyweight reps (Train H3 regression)

    func test_bodyweightPushUps_recordRepsPR_evenAtWeightZero() {
        _ = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [completedSet(weightKg: 0, reps: 20)]
        ))
        let pushUps25 = completedSet(weightKg: 0, reps: 25)
        let s = session(exerciseID: "test_pushups", sets: [pushUps25])

        let detections = PRDetectionEngine.shared.ingest(session: s)

        XCTAssertTrue(
            detections.contains { $0.kind == .bodyweightReps && $0.value == 25 },
            "Expected a bodyweightReps PR for 25 push-ups; got \(detections)"
        )
    }

    func test_firstEverLog_storesBaselineWithoutDetectingPRs() {
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_bench",
            sets: [completedSet(weightKg: 60, reps: 8)]
        ))
        XCTAssertTrue(detections.isEmpty, "Nothing to beat yet; got \(detections)")
        let record = SwiftDataRepository.shared.loadPersonalRecords()
            .first { $0.exerciseID == "test_bench" }
        XCTAssertEqual(record?.bestAbsoluteWeightKg, 60)
    }

    func test_bodyweightPushUps_betterSecondSession_firesAgain() {
        // 25 reps today
        _ = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [completedSet(weightKg: 0, reps: 25)]
        ))
        // 30 reps next session
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [completedSet(weightKg: 0, reps: 30)]
        ))
        XCTAssertTrue(
            detections.contains { $0.kind == .bodyweightReps && $0.value == 30 },
            "Improving from 25 → 30 should fire a fresh bodyweightReps PR"
        )
    }

    func test_bodyweightPushUps_sameReps_doesNotFireAgain() {
        _ = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [completedSet(weightKg: 0, reps: 25)]
        ))
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [completedSet(weightKg: 0, reps: 25)]
        ))
        XCTAssertFalse(
            detections.contains { $0.kind == .bodyweightReps },
            "Tying the previous bodyweight PR should not produce a new PR"
        )
    }

    func test_loadedLiftAtZeroKg_doesNotRecordRepsPR() async {
        await ExerciseLibrary.shared.load()
        _ = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: Self.barbellBenchID,
            sets: [completedSet(weightKg: 0, reps: 3)]
        ))
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: Self.barbellBenchID,
            sets: [completedSet(weightKg: 0, reps: 8)]
        ))
        XCTAssertFalse(
            detections.contains { $0.kind == .bodyweightReps },
            "A barbell set left at its seeded 0 kg isn't a bodyweight rep PR"
        )
    }

    // MARK: - Weighted PRs (smoke test for the existing tracks)

    func test_weightedSquat_recordsAllThreeWeightedKinds() {
        _ = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_squat",
            sets: [completedSet(weightKg: 90, reps: 5)]
        ))
        let topSet = completedSet(weightKg: 100, reps: 5)
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_squat",
            sets: [topSet]
        ))
        let kinds = Set(detections.map(\.kind))
        XCTAssertTrue(kinds.contains(.absoluteWeight))
        XCTAssertTrue(kinds.contains(.estimatedOneRepMax))
        XCTAssertTrue(kinds.contains(.sessionVolume))
        // No bodyweight track when the set carries a weight.
        XCTAssertFalse(kinds.contains(.bodyweightReps))
    }

    // MARK: - Ignored sets

    func test_warmupSets_doNotProducePRs() {
        let warmup = SetEntry(
            index: 1,
            weightKg: 0,
            reps: 50,
            completed: true,
            isWarmup: true
        )
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [warmup]
        ))
        XCTAssertTrue(detections.isEmpty, "Warm-up sets must be ignored by PR detection")
    }

    func test_incompleteSets_doNotProducePRs() {
        let incomplete = SetEntry(
            index: 1,
            weightKg: 0,
            reps: 100,
            completed: false
        )
        let detections = PRDetectionEngine.shared.ingest(session: session(
            exerciseID: "test_pushups",
            sets: [incomplete]
        ))
        XCTAssertTrue(detections.isEmpty, "Incomplete sets must be ignored by PR detection")
    }
}
