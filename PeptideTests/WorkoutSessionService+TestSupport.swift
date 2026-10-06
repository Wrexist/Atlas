import XCTest
@testable import Peptide

extension WorkoutSessionService {
    /// Starts a one-set workout and completes that set, because
    /// `finishWorkout` refuses a session with no completed working sets.
    @discardableResult
    func startWorkoutWithOneCompletedSet(file: StaticString = #filePath, line: UInt = #line) throws -> WorkoutSession {
        let started = startWorkout(routine: Routine(name: "Test", exercises: [
            RoutineExercise(exerciseID: "Incline_Dumbbell_Press", index: 0, targetSets: 1, targetReps: 10)
        ]))
        let entry = try XCTUnwrap(activeSession?.exercises.first, file: file, line: line)
        var set = try XCTUnwrap(entry.sets.first, file: file, line: line)
        set.completed = true
        set.weightKg = 25
        updateSet(set, inExerciseEntryID: entry.id)
        return started
    }
}
