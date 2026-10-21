import XCTest
@testable import Peptide

final class WorkoutStalenessEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let hour: TimeInterval = 3600

    private func session(completedAt: [Date?] = [], warmup: Bool = false) -> WorkoutSession {
        let sets = completedAt.enumerated().map { index, time in
            SetEntry(index: index + 1, weightKg: 60, reps: 8, completed: true, isWarmup: warmup, completedAt: time)
        }
        return WorkoutSession(startedAt: start, exercises: [
            WorkoutExerciseEntry(exerciseID: "Incline_Dumbbell_Press", index: 0, sets: sets)
        ])
    }

    // MARK: - Empty sessions

    func test_emptySession_idleUnderFourHours_isKept() {
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: session(), now: start.addingTimeInterval(4 * hour)), .keep)
    }

    func test_emptySession_idleOverFourHours_isDiscarded() {
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: session(), now: start.addingTimeInterval(4 * hour + 1)), .discard)
    }

    /// The bug report: 208 hours open, nothing logged.
    func test_emptySession_openForDays_isDiscarded() {
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: session(), now: start.addingTimeInterval(208 * hour)), .discard)
    }

    /// Warm-ups alone can't be finished (`finishWorkout` refuses), so they
    /// count as nothing logged.
    func test_warmupOnlySession_idleOverFourHours_isDiscarded() {
        let warmups = session(completedAt: [start.addingTimeInterval(60)], warmup: true)
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: warmups, now: start.addingTimeInterval(5 * hour)), .discard)
    }

    // MARK: - Sessions with logged sets

    func test_loggedSession_idleUnderSixHours_isKept() {
        let lastSet = start.addingTimeInterval(1800)
        let logged = session(completedAt: [lastSet])
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: logged, now: lastSet.addingTimeInterval(6 * hour)), .keep)
    }

    /// A long session is judged by its last set, not by when it started.
    func test_loggedSession_startedLongAgoButRecentSet_isKept() {
        let lastSet = start.addingTimeInterval(7 * hour)
        let logged = session(completedAt: [start.addingTimeInterval(60), lastSet])
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: logged, now: lastSet.addingTimeInterval(hour)), .keep)
    }

    func test_loggedSession_idleOverSixHours_finishesAtLastSetPlusBuffer() {
        let lastSet = start.addingTimeInterval(45 * 60)
        let logged = session(completedAt: [start.addingTimeInterval(600), lastSet, start.addingTimeInterval(1200)])
        XCTAssertEqual(
            WorkoutStalenessEngine.verdict(for: logged, now: start.addingTimeInterval(200 * hour)),
            .finish(at: lastSet.addingTimeInterval(WorkoutStalenessEngine.finishBuffer))
        )
    }

    /// Sets logged before `completedAt` existed carry no time; the start is
    /// the only trustworthy signal left.
    func test_loggedSessionWithoutSetTimestamps_finishesFromStart() {
        let legacy = session(completedAt: [nil])
        XCTAssertEqual(
            WorkoutStalenessEngine.verdict(for: legacy, now: start.addingTimeInterval(7 * hour)),
            .finish(at: start.addingTimeInterval(WorkoutStalenessEngine.finishBuffer))
        )
    }

    // MARK: - Paused and edge cases

    func test_pausedLoggedSession_finishesAfterThePause() {
        let lastSet = start.addingTimeInterval(1800)
        let pausedAt = start.addingTimeInterval(2400)
        var logged = session(completedAt: [lastSet])
        logged.focus = WorkoutFocusState(pausedAt: pausedAt)
        XCTAssertEqual(
            WorkoutStalenessEngine.verdict(for: logged, now: pausedAt.addingTimeInterval(7 * hour)),
            .finish(at: pausedAt.addingTimeInterval(WorkoutStalenessEngine.finishBuffer))
        )
    }

    /// Pausing doesn't exempt a session from being closed — days paused is
    /// still abandoned.
    func test_pausedEmptySession_idleOverFourHours_isDiscarded() {
        var empty = session()
        empty.focus = WorkoutFocusState(pausedAt: start.addingTimeInterval(60))
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: empty, now: start.addingTimeInterval(5 * hour)), .discard)
    }

    func test_finishedSession_isKept() {
        var done = session(completedAt: [start])
        done.finishedAt = start.addingTimeInterval(hour)
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: done, now: start.addingTimeInterval(100 * hour)), .keep)
    }

    /// A clock set back after logging must not seal a workout in the future.
    func test_lastActivityAfterNow_isKept() {
        let logged = session(completedAt: [start.addingTimeInterval(10 * hour)])
        XCTAssertEqual(WorkoutStalenessEngine.verdict(for: logged, now: start), .keep)
    }

    /// The auto-finished duration is the time actually trained, pauses
    /// excluded, rather than the days the session sat open.
    func test_autoFinishedSession_elapsedExcludesPauseAndIdle() {
        let lastSet = start.addingTimeInterval(1800)
        var logged = session(completedAt: [lastSet])
        logged.focus = WorkoutFocusState(pausedAt: start.addingTimeInterval(600))
        logged.focus?.resume(at: start.addingTimeInterval(900))
        let now = start.addingTimeInterval(48 * hour)
        guard case .finish(let end) = WorkoutStalenessEngine.verdict(for: logged, now: now) else {
            return XCTFail("Expected an auto-finish")
        }
        logged.finishedAt = end
        XCTAssertEqual(logged.elapsedSeconds(now: now), 1800 + Int(WorkoutStalenessEngine.finishBuffer) - 300)
    }
}

/// The Train tab's resume banner renders `WorkoutClock.label(elapsedSeconds)`.
final class WorkoutBannerClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func test_pausedSession_clockStopsAtPause() {
        var session = WorkoutSession(startedAt: start)
        session.focus = WorkoutFocusState(pausedAt: start.addingTimeInterval(125))
        XCTAssertEqual(WorkoutClock.label(session.elapsedSeconds(now: start.addingTimeInterval(125))), "2:05")
        XCTAssertEqual(WorkoutClock.label(session.elapsedSeconds(now: start.addingTimeInterval(9_000))), "2:05")
    }

    func test_resumedSession_clockExcludesPausedTime() {
        var session = WorkoutSession(startedAt: start)
        session.focus = WorkoutFocusState(pausedAt: start.addingTimeInterval(60))
        session.focus?.resume(at: start.addingTimeInterval(3_660))
        XCTAssertEqual(WorkoutClock.label(session.elapsedSeconds(now: start.addingTimeInterval(3_720))), "2:00")
    }

    func test_longSession_clockShowsHours() {
        let session = WorkoutSession(startedAt: start)
        XCTAssertEqual(WorkoutClock.label(session.elapsedSeconds(now: start.addingTimeInterval(3_725))), "1:02:05")
    }
}
