import XCTest
@testable import Peptide

final class RecoveryScoreEngineTests: XCTestCase {

    // MARK: - Empty / partial input handling

    func test_score_returnsNil_whenAllInputsAreMissing() {
        let result = RecoveryScoreEngine.score(inputs: .init())
        XCTAssertNil(result)
    }

    /// A user with only a sleep reading still gets a meaningful
    /// score — the missing component's weight redistributes across
    /// the available ones. Sleep at target hours → 100, partial-
    /// data flag set so the UI can prompt.
    func test_score_sleepOnly_returnsScaledScoreWithPartialFlag() {
        let result = RecoveryScoreEngine.score(inputs: .init(lastSleepHours: 8.0))
        guard let result else { return XCTFail("Expected score with partial inputs") }
        XCTAssertEqual(result.value, 100)
        XCTAssertTrue(result.isPartialData)
        XCTAssertNil(result.components.hrv)
        XCTAssertNil(result.components.rhr)
    }

    func test_score_allComponentsPresent_clearsPartialFlag() {
        let result = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 50,
            baselineHRV: 50,
            recentRHR: 60,
            baselineRHR: 60,
            lastSleepHours: 8.0
        ))
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isPartialData ?? true)
    }

    // MARK: - HRV component

    func test_hrvComponent_atBaseline_isMidRange() {
        // ratio = 1.0 sits in the middle of the floor=0.70 / ceiling=1.20 range.
        // (1.0 - 0.70) / (1.20 - 0.70) = 0.60.
        let value = RecoveryScoreEngine.hrvComponent(recent: 50, baseline: 50)
        XCTAssertEqual(value ?? 0, 0.60, accuracy: 0.01)
    }

    func test_hrvComponent_wellAboveBaseline_caps() {
        let value = RecoveryScoreEngine.hrvComponent(recent: 200, baseline: 50)
        XCTAssertEqual(value, 1.0)
    }

    func test_hrvComponent_wellBelowBaseline_floors() {
        let value = RecoveryScoreEngine.hrvComponent(recent: 10, baseline: 50)
        XCTAssertEqual(value, 0.0)
    }

    func test_hrvComponent_missingInputs_returnsNil() {
        XCTAssertNil(RecoveryScoreEngine.hrvComponent(recent: nil, baseline: 50))
        XCTAssertNil(RecoveryScoreEngine.hrvComponent(recent: 50, baseline: nil))
        // Zero baseline would divide by zero — must short-circuit to nil.
        XCTAssertNil(RecoveryScoreEngine.hrvComponent(recent: 50, baseline: 0))
    }

    // MARK: - Sleep component

    func test_sleepComponent_atTarget_isOne() {
        XCTAssertEqual(RecoveryScoreEngine.sleepComponent(hours: 8.0, target: 8.0), 1.0)
    }

    func test_sleepComponent_halfTarget_isHalf() {
        XCTAssertEqual(RecoveryScoreEngine.sleepComponent(hours: 4.0, target: 8.0) ?? 0, 0.5, accuracy: 0.001)
    }

    func test_sleepComponent_overTarget_clamps() {
        XCTAssertEqual(RecoveryScoreEngine.sleepComponent(hours: 12.0, target: 8.0), 1.0)
    }

    func test_sleepComponent_zeroHours_isZero() {
        XCTAssertEqual(RecoveryScoreEngine.sleepComponent(hours: 0, target: 8.0), 0.0)
    }

    // MARK: - RHR component (inverted: lower is better)

    func test_rhrComponent_belowBaseline_scoresHigh() {
        // ratio = 0.85 (15% lower) should hit the ceiling (1.0).
        let value = RecoveryScoreEngine.rhrComponent(recent: 51, baseline: 60)
        XCTAssertEqual(value ?? 0, 1.0, accuracy: 0.01)
    }

    func test_rhrComponent_aboveBaseline_scoresLow() {
        // ratio = 1.15 (15% higher) should hit the floor (0.0).
        let value = RecoveryScoreEngine.rhrComponent(recent: 69, baseline: 60)
        XCTAssertEqual(value ?? 0, 0.0, accuracy: 0.01)
    }

    func test_rhrComponent_atBaseline_isMidRange() {
        // ratio = 1.0 → inverted to (1.0 - 0.85) / (1.15 - 0.85) = 0.50.
        // Inverted: 1 - 0.50 = 0.50.
        let value = RecoveryScoreEngine.rhrComponent(recent: 60, baseline: 60)
        XCTAssertEqual(value ?? 0, 0.5, accuracy: 0.01)
    }

    // MARK: - Weighting

    /// All three components at 1.0 → overall score 100. Verifies the
    /// weights sum to 1.0 (anything else would scale the result).
    func test_score_allMaxComponents_isOneHundred() {
        let result = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 100, baselineHRV: 50,            // saturates to 1.0
            recentRHR: 40,  baselineRHR: 60,            // saturates to 1.0
            lastSleepHours: 9.0, sleepTargetHours: 8.0  // clamps to 1.0
        ))
        XCTAssertEqual(result?.value, 100)
    }

    /// All three at 0 → 0.
    func test_score_allMinComponents_isZero() {
        let result = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 10, baselineHRV: 50,
            recentRHR: 80, baselineRHR: 60,
            lastSleepHours: 0
        ))
        XCTAssertEqual(result?.value, 0)
    }

    /// Sleep at 100% + HRV at 100% but RHR missing → still high
    /// because the missing weight redistributes across the
    /// available components (not zeroed out).
    func test_score_missingRHR_doesNotPenaliseScore() {
        let withAll = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 100, baselineHRV: 50,
            recentRHR: 30,  baselineRHR: 60,
            lastSleepHours: 8.0
        ))
        let withoutRHR = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 100, baselineHRV: 50,
            lastSleepHours: 8.0
        ))
        // Both should peg at 100 — RHR can't make a perfect score
        // imperfect when it's missing, only when it's present and bad.
        XCTAssertEqual(withAll?.value, 100)
        XCTAssertEqual(withoutRHR?.value, 100)
    }

    // MARK: - Partial-data flag (audit Biology L16)

    /// Nil sleep is common (no Watch at bed). The score should NOT
    /// flag as partial when both cardio signals are present — that
    /// false alarm dimmed the badge every morning for Watch-only
    /// users.
    func test_isPartialData_falseWhenOnlySleepMissing() {
        let result = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 50, baselineHRV: 50,
            recentRHR: 60, baselineRHR: 60
            // no lastSleepHours
        ))
        XCTAssertEqual(result?.isPartialData, false)
    }

    /// HRV missing → partial, regardless of sleep / RHR presence.
    func test_isPartialData_trueWhenHRVMissing() {
        let result = RecoveryScoreEngine.score(inputs: .init(
            recentRHR: 60, baselineRHR: 60,
            lastSleepHours: 8.0
        ))
        XCTAssertEqual(result?.isPartialData, true)
    }

    /// RHR missing → partial.
    func test_isPartialData_trueWhenRHRMissing() {
        let result = RecoveryScoreEngine.score(inputs: .init(
            recentHRV: 50, baselineHRV: 50,
            lastSleepHours: 8.0
        ))
        XCTAssertEqual(result?.isPartialData, true)
    }
}
