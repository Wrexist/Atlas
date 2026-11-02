import XCTest
@testable import Peptide

@MainActor
final class MuscleRecoveryEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_793_534_400) // 2026-11-01 12:00 UTC
    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    func test_noHistory_everyMuscleReady() {
        let recovery = MuscleRecoveryEngine.recovery(from: [], library: library, now: now)
        XCTAssertEqual(recovery.count, AnatomicalMuscle.allCases.count)
        XCTAssertTrue(recovery.values.allSatisfy { $0.fraction == 1 && $0.status == .ready && $0.lastTrained == nil })
    }

    func test_fullSessionJustFinished_muscleMustRest() {
        let recovery = recovery(of: [curls(sets: 8, hoursAgo: 0)])
        XCTAssertEqual(recovery[.biceps]?.fraction, 0)
        XCTAssertEqual(recovery[.biceps]?.status, .rest)
        XCTAssertEqual(recovery[.biceps]?.lastTrained, now)
    }

    func test_fatigueFadesLinearlyOverRecoveryWindow() {
        let recovery = recovery(of: [curls(sets: 4, hoursAgo: 21)])
        XCTAssertEqual(recovery[.biceps]?.fraction ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(recovery[.biceps]?.status, .recovering)
    }

    func test_afterRecoveryWindow_muscleReadyButLastTrainedKept() {
        let recovery = recovery(of: [curls(sets: 8, hoursAgo: 42)])
        XCTAssertEqual(recovery[.biceps]?.fraction, 1)
        XCTAssertEqual(recovery[.biceps]?.lastTrained, now.addingTimeInterval(-42 * 3600))
    }

    func test_secondaryMusclesTireAtHalfRate() {
        let recovery = recovery(of: [curls(sets: 8, hoursAgo: 0)])
        XCTAssertEqual(recovery[.forearmFront]?.fraction ?? 0, 0.5, accuracy: 0.001)
    }

    func test_hardSetsTireMoreThanEasySets() {
        let easy = recovery(of: [curls(sets: 5, hoursAgo: 0)])
        let hard = recovery(of: [curls(sets: 5, hoursAgo: 0, rpe: 9.5)])
        XCTAssertEqual(easy[.biceps]?.fraction ?? 0, 0.375, accuracy: 0.001)
        XCTAssertEqual(hard[.biceps]?.fraction ?? 0, 0.25, accuracy: 0.001)
    }

    func test_lowReadiness_stretchesRecovery() {
        let sessions = [curls(sets: 8, hoursAgo: 42)]
        let normal = MuscleRecoveryEngine.recovery(from: sessions, library: library, readiness: .normal, now: now)
        let low = MuscleRecoveryEngine.recovery(from: sessions, library: library, readiness: .low, now: now)
        XCTAssertEqual(normal[.biceps]?.status, .ready)
        XCTAssertEqual(low[.biceps]?.fraction ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(low[.biceps]?.status, .recovering)
    }

    func test_warmupsAndFutureSessions_ignored() {
        let warmups = curls(sets: 0, hoursAgo: 1, warmups: 6)
        let future = curls(sets: 8, hoursAgo: -5)
        let recovery = recovery(of: [warmups, future])
        XCTAssertEqual(recovery[.biceps]?.fraction, 1)
        XCTAssertNil(recovery[.biceps]?.lastTrained)
    }

    func test_bigMusclesRecoverSlowerThanSmallOnes() {
        XCTAssertGreaterThan(MuscleRecoveryEngine.recoveryHours(for: .quadRectus),
                             MuscleRecoveryEngine.recoveryHours(for: .biceps))
    }

    func test_volumeTargets_remainingNeverNegative() {
        XCTAssertEqual(MuscleVolumeTargets.remainingSets(done: 4, experience: .intermediate), 8)
        XCTAssertEqual(MuscleVolumeTargets.remainingSets(done: 30, experience: .beginner), 0)
        XCTAssertLessThan(MuscleVolumeTargets.sessionCap(for: .beginner),
                          MuscleVolumeTargets.sessionCap(for: .expert))
    }

    // MARK: - Helpers

    private func recovery(of sessions: [WorkoutSession]) -> [AnatomicalMuscle: MuscleRecoveryEngine.Recovery] {
        MuscleRecoveryEngine.recovery(from: sessions, library: library, now: now)
    }

    private func curls(sets: Int, hoursAgo: Double, rpe: Double? = nil, warmups: Int = 0) -> WorkoutSession {
        let finished = now.addingTimeInterval(-hoursAgo * 3600)
        let warm = (0..<warmups).map { SetEntry(index: $0 + 1, weightKg: 6, reps: 10, completed: true, isWarmup: true) }
        let work = (0..<sets).map { SetEntry(index: warmups + $0 + 1, weightKg: 14, reps: 10, rpe: rpe, completed: true) }
        return WorkoutSession(
            startedAt: finished.addingTimeInterval(-3600),
            finishedAt: finished,
            exercises: [WorkoutExerciseEntry(exerciseID: "Dumbbell_Bicep_Curl", index: 0, sets: warm + work)]
        )
    }
}
