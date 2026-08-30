import XCTest
@testable import Peptide

/// The routine → session hand-off. Everything the user wrote down in the
/// builder has to survive into the active workout, and nothing they
/// mistyped is allowed to produce an unusable session.
final class RoutineSeedEngineTests: XCTestCase {

    private func slot(
        _ exerciseID: String,
        index: Int,
        sets: Int = 3,
        reps: Int = 10,
        rpe: Double? = nil,
        rest: Int? = nil,
        note: String? = nil
    ) -> RoutineExercise {
        RoutineExercise(
            exerciseID: exerciseID,
            index: index,
            targetSets: sets,
            targetReps: reps,
            targetRPE: rpe,
            restSeconds: rest,
            note: note
        )
    }

    // MARK: - Set seeding

    func test_sessionExercises_seedsOneEntryPerSlot_inRoutineOrder() {
        let routine = Routine(name: "Push", exercises: [
            slot("Barbell_Squat", index: 0),
            slot("Barbell_Curl", index: 1),
        ])

        let entries = RoutineSeedEngine.sessionExercises(for: routine)

        XCTAssertEqual(entries.map(\.exerciseID), ["Barbell_Squat", "Barbell_Curl"])
        XCTAssertEqual(entries.map(\.index), [0, 1])
    }

    /// The stored slot order is `index`, not array position — a routine
    /// round-tripped through JSON can arrive shuffled.
    func test_sessionExercises_sortsBySlotIndex_notArrayOrder() {
        let routine = Routine(name: "Pull", exercises: [
            slot("Barbell_Curl", index: 2),
            slot("Face_Pull", index: 0),
            slot("Seated_Cable_Rows", index: 1),
        ])

        let entries = RoutineSeedEngine.sessionExercises(for: routine)

        XCTAssertEqual(entries.map(\.exerciseID),
                       ["Face_Pull", "Seated_Cable_Rows", "Barbell_Curl"])
        XCTAssertEqual(entries.map(\.index), [0, 1, 2],
                       "Session indices are re-numbered contiguously from the sorted order")
    }

    func test_sessionExercises_seedsTargetSetsAndReps() {
        let routine = Routine(name: "5×5", exercises: [slot("Barbell_Squat", index: 0, sets: 5, reps: 5)])

        let sets = RoutineSeedEngine.sessionExercises(for: routine)[0].sets

        XCTAssertEqual(sets.count, 5)
        XCTAssertEqual(sets.map(\.index), [1, 2, 3, 4, 5], "Set rows display 1-indexed")
        XCTAssertTrue(sets.allSatisfy { $0.reps == 5 })
        XCTAssertTrue(sets.allSatisfy { !$0.completed },
                      "A seeded set is a target, not a logged set")
    }

    func test_sessionExercises_carriesTargetRPEOntoEverySet() {
        let routine = Routine(name: "RPE", exercises: [slot("Barbell_Squat", index: 0, sets: 2, rpe: 8)])

        let sets = RoutineSeedEngine.sessionExercises(for: routine)[0].sets

        XCTAssertEqual(sets.compactMap(\.rpe), [8, 8])
    }

    func test_sessionExercises_zeroTargetSets_stillSeedsOneRow() {
        let routine = Routine(name: "Broken", exercises: [slot("Plank", index: 0, sets: 0)])

        XCTAssertEqual(RoutineSeedEngine.sessionExercises(for: routine)[0].sets.count, 1,
                       "An exercise with no sets is unloggable — floor at one row")
    }

    func test_sessionExercises_absurdTargetSets_clampsToMax() {
        let routine = Routine(name: "Typo", exercises: [slot("Plank", index: 0, sets: 5_000)])

        XCTAssertEqual(RoutineSeedEngine.sessionExercises(for: routine)[0].sets.count,
                       RoutineSeedEngine.maxSeededSets)
    }

    func test_sessionExercises_outOfRangeReps_areClamped() {
        let routine = Routine(name: "Typo", exercises: [slot("Plank", index: 0, sets: 1, reps: -4)])

        XCTAssertEqual(RoutineSeedEngine.sessionExercises(for: routine)[0].sets[0].reps,
                       SetEntryLimits.reps.lowerBound)
    }

    func test_sessionExercises_emptyRoutine_seedsNothing() {
        XCTAssertTrue(RoutineSeedEngine.sessionExercises(for: Routine(name: "Empty")).isEmpty)
    }

    // MARK: - Previous-weight seeding

    func test_sessionExercises_seedsWeightFromPreviousSet() {
        let routine = Routine(name: "Push", exercises: [
            slot("Barbell_Squat", index: 0, sets: 2, reps: 5),
            slot("Barbell_Curl", index: 1, sets: 1),
        ])
        let history = ["Barbell_Squat": SetEntry(index: 1, weightKg: 102.5, reps: 3, completed: true)]

        let entries = RoutineSeedEngine.sessionExercises(for: routine) { history[$0] }

        XCTAssertTrue(entries[0].sets.allSatisfy { $0.weightKg == 102.5 },
                      "Every seeded set opens at the user's last working weight")
        XCTAssertTrue(entries[0].sets.allSatisfy { $0.reps == 5 },
                      "Reps come from the routine's target, not from history")
        XCTAssertEqual(entries[1].sets[0].weightKg, 0,
                       "No history for this lift means no guess")
    }

    // MARK: - Rest resolution

    func test_sessionExercises_slotRestWins_thenRoutineDefault() {
        let routine = Routine(
            name: "Rest",
            exercises: [
                slot("Barbell_Squat", index: 0, rest: 180),
                slot("Barbell_Curl", index: 1),
            ],
            defaultRestSeconds: 60
        )

        let entries = RoutineSeedEngine.sessionExercises(for: routine)

        XCTAssertEqual(entries[0].restSeconds, 180)
        XCTAssertEqual(entries[1].restSeconds, 60)
    }

    func test_sessionExercises_noRestAnywhere_leavesEntryNil() {
        let routine = Routine(name: "Rest", exercises: [slot("Barbell_Squat", index: 0)])

        XCTAssertNil(RoutineSeedEngine.sessionExercises(for: routine)[0].restSeconds,
                     "Nil defers to TrainingPreferences.restTimerDefault at render time")
    }

    func test_sessionExercises_carriesSlotNote() {
        let routine = Routine(name: "Tempo", exercises: [
            slot("Barbell_Squat", index: 0, note: "tempo 3-1-1"),
        ])

        XCTAssertEqual(RoutineSeedEngine.sessionExercises(for: routine)[0].note, "tempo 3-1-1")
    }

    // MARK: - Derived figures

    func test_totalSets_sumsClampedTargets() {
        let routine = Routine(name: "Legs", exercises: [
            slot("Barbell_Squat", index: 0, sets: 5),
            slot("Leg_Press", index: 1, sets: 3),
            slot("Plank", index: 2, sets: 0),
        ])

        XCTAssertEqual(RoutineSeedEngine.totalSets(in: routine), 9,
                       "The 0-set slot counts as the one row it will seed")
    }

    func test_estimatedMinutes_emptyRoutine_isZero() {
        XCTAssertEqual(RoutineSeedEngine.estimatedMinutes(for: Routine(name: "Empty")), 0)
    }

    func test_estimatedMinutes_countsWorkPlusRestBetweenSets() {
        // 3 sets × 40s work = 120s, plus 2 rests × 90s = 180s → 300s → 5 min.
        let routine = Routine(name: "One lift", exercises: [
            slot("Barbell_Squat", index: 0, sets: 3, rest: 90),
        ])

        XCTAssertEqual(RoutineSeedEngine.estimatedMinutes(for: routine), 5)
    }

    func test_estimatedMinutes_growsWithVolume() {
        let short = Routine(name: "Short", exercises: [slot("Barbell_Squat", index: 0, sets: 3)])
        let long = Routine(name: "Long", exercises: [
            slot("Barbell_Squat", index: 0, sets: 5),
            slot("Leg_Press", index: 1, sets: 4),
            slot("Lying_Leg_Curls", index: 2, sets: 4),
        ])

        XCTAssertGreaterThan(RoutineSeedEngine.estimatedMinutes(for: long),
                             RoutineSeedEngine.estimatedMinutes(for: short))
    }

    func test_estimatedMinutes_roundsToFiveMinuteSteps() {
        let routine = Routine(name: "Legs", exercises: [
            slot("Barbell_Squat", index: 0, sets: 4, rest: 120),
            slot("Leg_Press", index: 1, sets: 3, rest: 75),
        ])

        XCTAssertEqual(RoutineSeedEngine.estimatedMinutes(for: routine) % 5, 0,
                       "The estimate reads as an estimate, not a promise")
    }

    func test_estimatedMinutes_neverReadsAsZeroForARealRoutine() {
        let routine = Routine(name: "Tiny", exercises: [slot("Plank", index: 0, sets: 1, rest: 0)])

        XCTAssertGreaterThanOrEqual(RoutineSeedEngine.estimatedMinutes(for: routine), 5)
    }
}
