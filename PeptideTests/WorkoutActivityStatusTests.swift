import XCTest
@testable import Peptide

#if canImport(ActivityKit)
import ActivityKit

/// Pins the workout Live Activity's state machine and the session →
/// content-state mapping. Both are pure, and both decide what four
/// separate surfaces (lock screen, compact pill, expanded island,
/// minimal glyph) render — a drift here shows up on a lock screen with
/// nothing to catch it.
@available(iOS 16.1, *)
final class WorkoutActivityStatusTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_749_643_200)

    private func state(
        restEndsAt: Date? = nil,
        restTotalSeconds: Double = 0,
        finishedAt: Date? = nil,
        completedSets: Int = 0,
        totalSets: Int = 0,
        name: String = "Push A"
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            workoutName: name,
            currentExercise: "Bench Press",
            completedSets: completedSets,
            totalSets: totalSets,
            exerciseCount: 3,
            restEndsAt: restEndsAt,
            restTotalSeconds: restTotalSeconds,
            finishedAt: finishedAt
        )
    }

    // MARK: - Status

    func test_noRestTarget_isLifting() {
        XCTAssertEqual(state().status(at: now), .lifting)
    }

    func test_futureRestTarget_isRestingWithSecondsRemaining() {
        let s = state(restEndsAt: now.addingTimeInterval(45), restTotalSeconds: 90)
        XCTAssertEqual(s.status(at: now), .resting(secondsRemaining: 45))
    }

    func test_elapsedRestTarget_fallsBackToLifting() {
        // No "rest is up" state to clear: the local notification already
        // buzzed, and a state the app has to reset is a state it can
        // fail to reset.
        let s = state(restEndsAt: now.addingTimeInterval(-1), restTotalSeconds: 90)
        XCTAssertEqual(s.status(at: now), .lifting)
    }

    func test_restTargetExactlyNow_isNoLongerResting() {
        let s = state(restEndsAt: now, restTotalSeconds: 90)
        XCTAssertEqual(s.status(at: now), .lifting)
    }

    func test_finishedBeatsEveryOtherState() {
        let s = state(restEndsAt: now.addingTimeInterval(45), restTotalSeconds: 90, finishedAt: now)
        XCTAssertEqual(s.status(at: now), .finished)
    }

    // MARK: - Rest interval

    func test_restInterval_spansTheRestEndingAtItsTarget() {
        let endsAt = now.addingTimeInterval(30)
        let s = state(restEndsAt: endsAt, restTotalSeconds: 120)
        XCTAssertEqual(s.restInterval, endsAt.addingTimeInterval(-120)...endsAt)
    }

    func test_restInterval_isNilWithNoRest() {
        XCTAssertNil(state().restInterval)
    }

    func test_restInterval_negativeTotal_doesNotInvertTheRange() {
        // `ProgressView(timerInterval:)` traps on an inverted range.
        let endsAt = now.addingTimeInterval(30)
        let s = state(restEndsAt: endsAt, restTotalSeconds: -10)
        XCTAssertEqual(s.restInterval, endsAt...endsAt)
    }

    // MARK: - Set progress

    func test_setProgress_isTheCompletedFraction() {
        XCTAssertEqual(state(completedSets: 6, totalSets: 12).setProgress, 0.5, accuracy: 0.0001)
    }

    func test_setProgress_isZeroWithNoPlannedSets() {
        XCTAssertEqual(state(completedSets: 3, totalSets: 0).setProgress, 0)
    }

    func test_setProgress_clampsWhenExtraSetsAreLogged() {
        XCTAssertEqual(state(completedSets: 14, totalSets: 12).setProgress, 1)
    }

    // MARK: - Idle

    func test_isIdle_notStale_isFalse() {
        XCTAssertFalse(state().isIdle(isStale: false, at: now))
    }

    func test_isIdle_staleWithNoRest_isTrue() {
        XCTAssertTrue(state().isIdle(isStale: true, at: now))
    }

    func test_isIdle_staleAtTheEndOfARest_isFalse() {
        // The rest's end is the stale date; that redraw is the countdown
        // finishing, not the workout being forgotten.
        let s = state(restEndsAt: now.addingTimeInterval(-5), restTotalSeconds: 90)
        XCTAssertFalse(s.isIdle(isStale: true, at: now))
    }

    func test_isIdle_staleLongAfterTheLastRest_isTrue() {
        let s = state(restEndsAt: now.addingTimeInterval(-3 * 3600), restTotalSeconds: 90)
        XCTAssertTrue(s.isIdle(isStale: true, at: now))
    }

    func test_isIdle_finished_isFalse() {
        XCTAssertFalse(state(finishedAt: now).isIdle(isStale: true, at: now))
    }

    // MARK: - Display name

    func test_displayName_fallsBackForAnUnnamedWorkout() {
        XCTAssertEqual(state(name: "").displayName, "Workout")
        XCTAssertEqual(state(name: "Leg Day").displayName, "Leg Day")
    }

    // MARK: - Session mapping

    @MainActor
    func test_stateForSession_countsWorkingSetsOnly() {
        let session = WorkoutSession(
            name: "Pull B",
            startedAt: now,
            exercises: [
                WorkoutExerciseEntry(exerciseID: "a", index: 0, sets: [
                    SetEntry(index: 1, weightKg: 60, reps: 10, completed: true, isWarmup: true),
                    SetEntry(index: 2, weightKg: 100, reps: 5, completed: true),
                    SetEntry(index: 3, weightKg: 100, reps: 5),
                ]),
                WorkoutExerciseEntry(exerciseID: "b", index: 1, sets: [
                    SetEntry(index: 1, weightKg: 40, reps: 12),
                ]),
            ]
        )

        let mapped = WorkoutLiveActivityService.state(for: session)

        XCTAssertEqual(mapped.workoutName, "Pull B")
        XCTAssertEqual(mapped.exerciseCount, 2)
        XCTAssertEqual(mapped.completedSets, 1)  // the warm-up doesn't count
        XCTAssertEqual(mapped.totalSets, 3)      // nor toward the plan
        XCTAssertNil(mapped.finishedAt)
        XCTAssertNil(mapped.restEndsAt)
    }

    @MainActor
    func test_stateForSession_startsWithNoRestInFlight() {
        // Rest is pushed separately by `updateRest` — a set being logged
        // must never reset a countdown the user is still waiting on.
        let mapped = WorkoutLiveActivityService.state(
            for: WorkoutSession(startedAt: now)
        )
        XCTAssertNil(mapped.restEndsAt)
        XCTAssertEqual(mapped.restTotalSeconds, 0)
        XCTAssertEqual(mapped.displayName, "Workout")
    }

    // MARK: - Stale date

    func test_staleDate_whileResting_isTheEndOfTheRest() {
        let endsAt = now.addingTimeInterval(90)
        let stale = state(restEndsAt: endsAt, restTotalSeconds: 120).staleDate(now: now)
        XCTAssertEqual(stale, endsAt)
    }

    func test_staleDate_restAlreadyOver_isTwoHoursOut() {
        let stale = state(restEndsAt: now.addingTimeInterval(-5), restTotalSeconds: 120).staleDate(now: now)
        XCTAssertEqual(stale, now.addingTimeInterval(2 * 3600))
    }

    func test_staleDate_afterSkippingARest_isTheIdleIntervalOut() {
        // The Skip rest button clears the rest on the activity; keeping
        // the rest's end as the stale date would grey a live workout
        // out as idle the moment that end passed.
        var skipped = state(restEndsAt: now.addingTimeInterval(90), restTotalSeconds: 120)
        skipped.restEndsAt = nil
        skipped.restTotalSeconds = 0
        XCTAssertEqual(skipped.staleDate(now: now), now.addingTimeInterval(2 * 3600))
    }
}
#endif
