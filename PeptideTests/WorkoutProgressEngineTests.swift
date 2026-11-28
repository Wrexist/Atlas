import XCTest
@testable import Peptide

final class WorkoutProgressEngineTests: XCTestCase {
    private typealias Engine = WorkoutProgressEngine

    private func set(_ index: Int, kg: Double = 60, reps: Int = 8, done: Bool = false, warmup: Bool = false) -> SetEntry {
        SetEntry(index: index, weightKg: kg, reps: reps, completed: done, isWarmup: warmup)
    }

    private func session(_ exercises: [[SetEntry]]) -> WorkoutSession {
        WorkoutSession(exercises: exercises.enumerated().map { index, sets in
            WorkoutExerciseEntry(exerciseID: "ex-\(index)", index: index, sets: sets)
        })
    }

    private func completing(_ session: WorkoutSession, exercise: Int, set: Int) -> WorkoutSession {
        var copy = session
        copy.exercises[exercise].sets[set].completed = true
        return copy
    }

    // MARK: - Progress

    func test_progress_countsWorkingSetsOnly_andSkipsWarmupOnlyExercises() {
        let progress = Engine.progress(of: session([
            [set(0, done: true, warmup: true), set(1, done: true), set(2), set(3)],
            [set(0, warmup: true)],
            [set(0, done: true)],
        ]))
        XCTAssertEqual(progress.segments.count, 2)
        XCTAssertEqual(progress.done, 2)
        XCTAssertEqual(progress.total, 4)
        XCTAssertEqual(progress.percent, 50)
    }

    func test_percent_roundsDown_soHundredMeansEverySetDone() {
        let sets = (0..<200).map { set($0, done: $0 < 199) }
        XCTAssertEqual(Engine.progress(of: session([sets])).percent, 99)
    }

    func test_progress_emptySession_isZero() {
        let progress = Engine.progress(of: session([]))
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(Engine.status(for: progress), .start)
    }

    // MARK: - Status

    func test_status_followsRemainingSets() {
        func status(done: Int, of total: Int) -> Engine.Status {
            Engine.status(for: Engine.progress(of: session([(0..<total).map { set($0, done: $0 < done) }])))
        }
        XCTAssertEqual(status(done: 0, of: 10), .start)
        XCTAssertEqual(status(done: 2, of: 10), .setsToGo(8))
        XCTAssertEqual(status(done: 5, of: 10), .setsToGo(5))
        XCTAssertEqual(status(done: 6, of: 10), .pastHalfway(4))
        XCTAssertEqual(status(done: 8, of: 10), .almostThere(2))
        XCTAssertEqual(status(done: 15, of: 20), .almostThere(5))
        XCTAssertEqual(status(done: 9, of: 10), .lastSet)
        XCTAssertEqual(status(done: 1, of: 4), .setsToGo(3))
        XCTAssertEqual(status(done: 10, of: 10), .allDone)
    }

    // MARK: - Milestones

    func test_milestone_returnsHighestCrossedGoingUp() {
        XCTAssertEqual(Engine.milestone(from: 20, to: 25), 25)
        XCTAssertEqual(Engine.milestone(from: 20, to: 60), 50)
        XCTAssertNil(Engine.milestone(from: 50, to: 60))
        XCTAssertNil(Engine.milestone(from: 60, to: 40))
        XCTAssertNil(Engine.milestone(from: 80, to: 100))
    }

    // MARK: - Gain on last time

    func test_gain_heavierWithSameReps_isWeightGain() {
        XCTAssertEqual(Engine.gain(set(0, kg: 62.5, reps: 8), over: set(0, kg: 60, reps: 8)), .weight(kg: 2.5))
    }

    func test_gain_moreRepsAtSameWeight_isRepGain() {
        XCTAssertEqual(Engine.gain(set(0, kg: 60, reps: 10), over: set(0, kg: 60, reps: 8)), .reps(2))
    }

    func test_gain_sameSet_isMatched() {
        XCTAssertEqual(Engine.gain(set(0), over: set(0)), .matched)
    }

    func test_gain_shortfallOrNoHistory_isNil() {
        XCTAssertNil(Engine.gain(set(0, kg: 65, reps: 5), over: set(0, kg: 60, reps: 8)))
        XCTAssertNil(Engine.gain(set(0, kg: 55, reps: 8), over: set(0, kg: 60, reps: 8)))
        XCTAssertNil(Engine.gain(set(0), over: nil))
    }

    // MARK: - Newly completed set

    func test_newlyCompleted_findsTheOneCheckedSet() {
        let before = session([[set(0, done: true), set(1)], [set(0)]])
        let after = completing(before, exercise: 0, set: 1)
        let found = Engine.newlyCompleted(before: before, after: after)
        XCTAssertEqual(found?.set.id, after.exercises[0].sets[1].id)
        XCTAssertEqual(found?.entry.id, after.exercises[0].id)
    }

    func test_newlyCompleted_ignoresUncheckWarmupAndBulkChanges() {
        let base = session([[set(0, warmup: true), set(1), set(2)]])
        XCTAssertNil(Engine.newlyCompleted(before: completing(base, exercise: 0, set: 1), after: base))
        XCTAssertNil(Engine.newlyCompleted(before: base, after: completing(base, exercise: 0, set: 0)))
        let both = completing(completing(base, exercise: 0, set: 1), exercise: 0, set: 2)
        XCTAssertNil(Engine.newlyCompleted(before: base, after: both))
    }

    func test_newlyCompleted_differentSession_isNil() {
        let before = session([[set(0)]])
        let other = completing(session([[set(0)]]), exercise: 0, set: 0)
        XCTAssertNil(Engine.newlyCompleted(before: before, after: other))
    }

    // MARK: - Reward

    func test_reward_exerciseDoneBeatsGain() {
        let before = session([[set(0, done: true), set(1)], [set(0)]])
        let after = completing(before, exercise: 0, set: 1)
        let reward = Engine.reward(entry: after.exercises[0], gain: .weight(kg: 2.5),
                                   before: Engine.progress(of: before), after: Engine.progress(of: after))
        XCTAssertEqual(reward, .exerciseDone)
    }

    func test_reward_gainBeatsMilestone_butMatchedDoesNot() {
        let before = session([[set(0), set(1), set(2), set(3)]])
        let after = completing(before, exercise: 0, set: 0)
        let old = Engine.progress(of: before), new = Engine.progress(of: after)
        XCTAssertEqual(Engine.reward(entry: after.exercises[0], gain: .reps(1), before: old, after: new), .gain(.reps(1)))
        XCTAssertEqual(Engine.reward(entry: after.exercises[0], gain: .matched, before: old, after: new), .milestone(25))
        XCTAssertEqual(Engine.reward(entry: after.exercises[0], gain: nil, before: old, after: new), .milestone(25))
    }

    func test_reward_lastSetOfWorkout_isNil_soTheFinishStatusShows() {
        let before = session([[set(0, done: true), set(1)]])
        let after = completing(before, exercise: 0, set: 1)
        XCTAssertNil(Engine.reward(entry: after.exercises[0], gain: .weight(kg: 5),
                                   before: Engine.progress(of: before), after: Engine.progress(of: after)))
    }
}
