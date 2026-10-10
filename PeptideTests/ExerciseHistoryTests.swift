import XCTest
@testable import Peptide

final class ExerciseHistoryTests: XCTestCase {
    private func session(_ sets: [SetEntry], date: Date = Date()) -> WorkoutSession {
        WorkoutSession(startedAt: date, finishedAt: date.addingTimeInterval(60),
                       exercises: [WorkoutExerciseEntry(exerciseID: "test", index: 0, sets: sets)])
    }

    func testExcludesActiveWarmupsIncompleteAndOtherExercises() {
        let working = SetEntry(index: 1, weightKg: 20, reps: 10, completed: true)
        let warmup = SetEntry(index: 2, weightKg: 10, reps: 10, completed: true, isWarmup: true)
        let unfinished = SetEntry(index: 3, weightKg: 20, reps: 10)
        let saved = session([working, warmup, unfinished])
        var active = session([working])
        active.finishedAt = nil
        let visits = ExerciseHistoryEngine.visits(exerciseID: "test", sessions: [saved, active], catalog: [:])
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.sets.map(\.id), [working.id])
        XCTAssertTrue(ExerciseHistoryEngine.visits(exerciseID: "other", sessions: [saved], catalog: [:]).isEmpty)
    }

    func testDeduplicatesSessionsEntriesAndSetsAndUsesLatestFirst() {
        let set = SetEntry(index: 1, weightKg: 20, reps: 10, completed: true)
        var older = session([set, set], date: Date(timeIntervalSince1970: 100))
        older.exercises.append(older.exercises[0])
        older.exercises.append(WorkoutExerciseEntry(exerciseID: "test", index: 1, sets: [set]))
        let newer = session([set], date: Date(timeIntervalSince1970: 200))
        let visits = ExerciseHistoryEngine.visits(exerciseID: "test", sessions: [older, newer, older], catalog: [:])
        XCTAssertEqual(visits.map(\.id), [newer.id, older.id])
        XCTAssertEqual(visits.map { $0.sets.count }, [1, 1])
    }

    func testPreservesMeasurementConventionsAndReflectsEdits() {
        var paired = SetEntry(index: 1, weightKg: 20, reps: 10, completed: true)
        paired.measurement = .init(kind: .repetitions, load: .eachPair)
        var timed = SetEntry(index: 2, weightKg: 0, reps: 0, completed: true)
        timed.measurement = .init(kind: .timed, seconds: 45)
        var saved = session([paired, timed])
        let first = ExerciseHistoryEngine.visits(exerciseID: "test", sessions: [saved], catalog: [:])
        XCTAssertEqual(first.first?.sets, [paired, timed])
        saved.exercises[0].sets[0].reps = 12
        let edited = ExerciseHistoryEngine.visits(exerciseID: "test", sessions: [saved], catalog: [:])
        XCTAssertEqual(edited.first?.id, first.first?.id)
        XCTAssertEqual(edited.first?.sets.first?.reps, 12)
        XCTAssertEqual(edited.first?.sets.first?.measurement?.load, .eachPair)
        XCTAssertEqual(edited.first?.sets.last?.measurement?.seconds, 45)
    }
}
