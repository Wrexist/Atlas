import XCTest
@testable import Peptide

/// Pins the pure decisions behind the Siri actions — weight units and
/// range, the "already fasting" guard, and which routines Siri offers —
/// without the App Intents runtime.
@MainActor
final class SiriActionIntentTests: XCTestCase {

    /// 2026-10-21 08:00 UTC.
    private let morning = Date(timeIntervalSince1970: 1_792_569_600)

    // MARK: - Log weight

    func test_kilograms_metricValue_isTakenAsKilograms() {
        XCTAssertEqual(LogWeightIntent.kilograms(82.4, unit: .metric), 82.4)
    }

    func test_kilograms_imperialValue_convertsPoundsToKilograms() {
        XCTAssertEqual(LogWeightIntent.kilograms(181.6, unit: .imperial) ?? 0, 82.37, accuracy: 0.01)
    }

    func test_kilograms_misheardDecimal_isRejected() {
        XCTAssertNil(LogWeightIntent.kilograms(8.24, unit: .metric))
    }

    func test_kilograms_poundsAboveRange_isRejected() {
        XCTAssertNil(LogWeightIntent.kilograms(900, unit: .imperial))
    }

    func test_kilograms_rangeBounds_areAccepted() {
        XCTAssertEqual(LogWeightIntent.kilograms(25, unit: .metric), 25)
        XCTAssertEqual(LogWeightIntent.kilograms(350, unit: .metric), 350)
    }

    // MARK: - Fasting

    private func fast(startedAt: Date, hours: Double = 16, endedAt: Date? = nil) -> FastSession {
        FastSession(startedAt: startedAt, endedAt: endedAt, targetHours: hours, plan: .sixteen)
    }

    func test_startDecision_noOpenFast_starts() {
        XCTAssertEqual(FastingIntentEngine.startDecision(active: nil), .start)
    }

    func test_startDecision_fastRunning_reportsAlreadyFastingSinceItsStart() {
        let running = fast(startedAt: morning)

        XCTAssertEqual(FastingIntentEngine.startDecision(active: running), .alreadyFasting(since: morning))
    }

    func test_endDecision_noOpenFast_reportsNotFasting() {
        XCTAssertEqual(FastingIntentEngine.endDecision(active: nil, at: morning), .notFasting)
    }

    func test_endDecision_beforeGoal_endsShortOfIt() {
        let running = fast(startedAt: morning)
        let now = morning.addingTimeInterval(10 * 3_600)

        XCTAssertEqual(
            FastingIntentEngine.endDecision(active: running, at: now),
            .end(elapsed: 10 * 3_600, reachedGoal: false, targetHours: 16)
        )
    }

    func test_endDecision_pastGoal_endsWithGoalReached() {
        let running = fast(startedAt: morning)
        let now = morning.addingTimeInterval(17 * 3_600)

        XCTAssertEqual(
            FastingIntentEngine.endDecision(active: running, at: now),
            .end(elapsed: 17 * 3_600, reachedGoal: true, targetHours: 16)
        )
    }

    // MARK: - Start workout routines

    private func routine(_ name: String, empty: Bool = false) -> Routine {
        Routine(name: name, exercises: empty ? [] : [RoutineExercise(exerciseID: "squat", index: 0)])
    }

    func test_startable_afterPush_putsPullFirstAndKeepsLibraryOrder() {
        let push = routine("Push"), pull = routine("Pull"), legs = routine("Legs")
        let history = [WorkoutSession(routineID: push.id, startedAt: morning, finishedAt: morning.addingTimeInterval(3_600))]

        let ordered = RoutineEntityQuery.startable([push, pull, legs], history: history)

        XCTAssertEqual(ordered.map(\.name), ["Pull", "Push", "Legs"])
    }

    func test_startable_emptyRoutine_isLeftOut() {
        let draft = routine("Draft", empty: true), push = routine("Push")

        XCTAssertEqual(RoutineEntityQuery.startable([draft, push], history: []).map(\.name), ["Push"])
    }
}
