import XCTest
@testable import Peptide

final class TrainingLevelEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(sets: Int, warmups: Int = 0, startOffset: TimeInterval = 0,
                         finished: Bool = true) -> WorkoutSession {
        let working = (0..<sets).map { SetEntry(index: $0, weightKg: 60, reps: 8, completed: true) }
        let warm = (0..<warmups).map { SetEntry(index: sets + $0, weightKg: 20, reps: 8, completed: true, isWarmup: true) }
        let skipped = SetEntry(index: sets + warmups, weightKg: 60, reps: 8, completed: false)
        let begin = start.addingTimeInterval(startOffset)
        return WorkoutSession(startedAt: begin,
                              finishedAt: finished ? begin.addingTimeInterval(3600) : nil,
                              exercises: [WorkoutExerciseEntry(exerciseID: "bench", index: 0,
                                                               sets: working + warm + [skipped])])
    }

    func test_xp_countsOnlyCompletedWorkingSets() {
        XCTAssertEqual(TrainingLevelEngine.xp(for: session(sets: 3, warmups: 2)), 20 + 3 * 5)
    }

    func test_xp_emptyOrActiveSessionEarnsNothing() {
        XCTAssertEqual(TrainingLevelEngine.xp(for: session(sets: 0)), 0)
        XCTAssertEqual(TrainingLevelEngine.xp(for: session(sets: 10, finished: false)), 0)
    }

    func test_xp_capsVeryLongSessions() {
        XCTAssertEqual(TrainingLevelEngine.xp(for: session(sets: 200)),
                       20 + TrainingLevelEngine.maxCountedSets * 5)
    }

    func test_progress_levelsGetFurtherApart() {
        XCTAssertEqual(TrainingLevelEngine.progress(totalXP: 0).level, 1)
        XCTAssertEqual(TrainingLevelEngine.progress(totalXP: 99).level, 1)
        let two = TrainingLevelEngine.progress(totalXP: 100)
        XCTAssertEqual(two.level, 2)
        XCTAssertEqual(two.xpIntoLevel, 0)
        XCTAssertEqual(two.xpForNextLevel, 140)
        let three = TrainingLevelEngine.progress(totalXP: 250)
        XCTAssertEqual(three.level, 3)
        XCTAssertEqual(three.xpIntoLevel, 10)
        XCTAssertEqual(three.xpToNextLevel, 170)
    }

    func test_gain_countsOnlyEarlierWorkoutsAsBefore() {
        let earlier = session(sets: 10, startOffset: -86_400)
        let later = session(sets: 10, startOffset: 86_400)
        let current = session(sets: 4)
        let gain = TrainingLevelEngine.gain(for: current, history: [earlier, current, later])
        XCTAssertEqual(gain.before.totalXP, 70)
        XCTAssertEqual(gain.earnedXP, 40)
        XCTAssertEqual(gain.levelsGained, 1)
        XCTAssertEqual(gain.after.level, 2)
    }

    func test_gain_firstWorkoutStartsAtLevelOne() {
        let gain = TrainingLevelEngine.gain(for: session(sets: 6), history: [])
        XCTAssertEqual(gain.before, TrainingLevelEngine.progress(totalXP: 0))
        XCTAssertEqual(gain.earnedXP, 50)
        XCTAssertEqual(gain.levelsGained, 0)
    }
}
