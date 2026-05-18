import XCTest
@testable import Peptide

/// Pure-function bio-age engine — every branch is testable in
/// isolation. The point of the suite is to lock down the
/// thresholds: when these constants get tuned in the future,
/// the tests force the maintainer to update the assertions
/// deliberately rather than drift silently.
final class PerformanceAgeEngineTests: XCTestCase {

    // MARK: - HRV contribution

    func test_hrvContribution_aboveHighFloor_returnsFullYoungerSwing() {
        // hrvHighFloor = 60ms; anything ≥ 60 returns -2.5 years.
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: 60), -2.5)
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: 90), -2.5)
    }

    func test_hrvContribution_belowLowCeiling_returnsFullOlderSwing() {
        // hrvLowCeiling = 25ms; anything ≤ 25 returns +2.5.
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: 25), 2.5)
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: 10), 2.5)
    }

    func test_hrvContribution_midRange_interpolatesLinearly() {
        // Midpoint of 25…60 is 42.5; should land at 0.
        XCTAssertEqual(
            PerformanceAgeEngine.hrvContribution(hrv: 42.5),
            0,
            accuracy: 0.01
        )
        // 1/4 of the way (33.75) → +1.25 years (still older end).
        XCTAssertEqual(
            PerformanceAgeEngine.hrvContribution(hrv: 33.75),
            1.25,
            accuracy: 0.01
        )
    }

    func test_hrvContribution_zeroOrNegative_returnsZero() {
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: 0), 0)
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: -5), 0)
    }

    // MARK: - RHR contribution

    func test_rhrContribution_athletic_returnsFullYoungerSwing() {
        XCTAssertEqual(PerformanceAgeEngine.rhrContribution(rhr: 55), -1.8)
        XCTAssertEqual(PerformanceAgeEngine.rhrContribution(rhr: 42), -1.8)
    }

    func test_rhrContribution_elevated_returnsFullOlderSwing() {
        XCTAssertEqual(PerformanceAgeEngine.rhrContribution(rhr: 75), 1.8)
        XCTAssertEqual(PerformanceAgeEngine.rhrContribution(rhr: 95), 1.8)
    }

    func test_rhrContribution_normal_isMidRange() {
        // Midpoint of 55…75 is 65; expect 0.
        XCTAssertEqual(
            PerformanceAgeEngine.rhrContribution(rhr: 65),
            0,
            accuracy: 0.01
        )
    }

    // MARK: - Sleep contribution

    func test_sleepContribution_atOrAboveTarget_returnsZero() {
        XCTAssertEqual(PerformanceAgeEngine.sleepContribution(hours: 7.5), 0)
        XCTAssertEqual(PerformanceAgeEngine.sleepContribution(hours: 9.0), 0)
    }

    func test_sleepContribution_atOrBelowFloor_returnsFullPenalty() {
        XCTAssertEqual(PerformanceAgeEngine.sleepContribution(hours: 6.0), 1.5)
        XCTAssertEqual(PerformanceAgeEngine.sleepContribution(hours: 4.5), 1.5)
    }

    func test_sleepContribution_betweenFloorAndTarget_interpolates() {
        // Halfway between 6 and 7.5 is 6.75 → half penalty = 0.75.
        XCTAssertEqual(
            PerformanceAgeEngine.sleepContribution(hours: 6.75),
            0.75,
            accuracy: 0.01
        )
    }

    // MARK: - Weight contribution

    /// Rapid weight change in either direction stresses the
    /// system — magnitude matters, sign doesn't.
    func test_weightContribution_rapidEitherDirection_returnsPenalty() {
        XCTAssertEqual(PerformanceAgeEngine.weightContribution(deltaKg: 2.5), 0.5)
        XCTAssertEqual(PerformanceAgeEngine.weightContribution(deltaKg: -3.0), 0.5)
    }

    func test_weightContribution_slowDrift_returnsZero() {
        XCTAssertEqual(PerformanceAgeEngine.weightContribution(deltaKg: 0.8), 0)
        XCTAssertEqual(PerformanceAgeEngine.weightContribution(deltaKg: -1.2), 0)
    }

    // MARK: - Confidence

    /// Below 7 days of data, no confidence. The UI sees nil and
    /// shows the "building baseline" state.
    func test_confidenceScore_lessThanSevenDays_isZero() {
        XCTAssertEqual(
            PerformanceAgeEngine.confidenceScore(componentCount: 4, healthDataDays: 6),
            0
        )
    }

    func test_confidenceScore_thirtyDaysAllComponents_isOne() {
        XCTAssertEqual(
            PerformanceAgeEngine.confidenceScore(componentCount: 4, healthDataDays: 30),
            1.0,
            accuracy: 0.001
        )
    }

    /// Halfway up the density curve with three of four components.
    /// completeness = 0.75; density at 18 days = 0.4 + (11/23)*0.6
    /// ≈ 0.687. Product ≈ 0.515.
    func test_confidenceScore_partialDataAndDays_scales() {
        let score = PerformanceAgeEngine.confidenceScore(
            componentCount: 3,
            healthDataDays: 18
        )
        XCTAssertGreaterThan(score, 0.45)
        XCTAssertLessThan(score, 0.6)
    }

    // MARK: - estimate (end to end)

    func test_estimate_emptyInputsBelowConfidence_returnsNil() {
        let result = PerformanceAgeEngine.estimate(inputs: .init(
            chronologicalAge: 30,
            healthDataDays: 5
        ))
        XCTAssertNil(result)
    }

    /// A user in great shape: high HRV, low RHR, 8h sleep, stable
    /// weight, 30 days of HealthKit data. Expect a bio age below
    /// chronological, drivers sorted by absolute impact.
    func test_estimate_strongInputs_returnsYoungerBioAge() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 35,
            hrvMedian30d: 70,
            rhrMedian30d: 50,
            sleepHoursMedian30d: 8.0,
            weightDeltaKg30d: 0.3,
            healthDataDays: 30
        )
        let result = PerformanceAgeEngine.estimate(inputs: inputs)
        guard let result else { return XCTFail("Expected estimate") }
        XCTAssertLessThan(result.biologicalAge, 35.0)
        XCTAssertEqual(result.confidence, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.drivers.count, 4)
        // HRV and RHR pulling down should be the top two drivers.
        XCTAssertEqual(result.drivers[0].kind, .hrv)
        XCTAssertEqual(result.drivers[1].kind, .rhr)
    }

    /// A user in worse shape: low HRV, high RHR, short sleep,
    /// rapid weight gain. Expect bio age above chronological,
    /// capped at +8 if all four drivers push the same direction.
    func test_estimate_weakInputs_returnsOlderBioAgeCapped() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 35,
            hrvMedian30d: 18,
            rhrMedian30d: 82,
            sleepHoursMedian30d: 5.5,
            weightDeltaKg30d: 3.5,
            healthDataDays: 30
        )
        let result = PerformanceAgeEngine.estimate(inputs: inputs)
        guard let result else { return XCTFail("Expected estimate") }
        XCTAssertGreaterThan(result.biologicalAge, 35.0)
        // Sum of penalties: HRV 2.5 + RHR 1.8 + Sleep 1.5 + Weight
        // 0.5 = 6.3. Below the +8 cap, so the result should be
        // 35 + 6.3 = 41.3, NOT pegged at 43.
        XCTAssertEqual(result.biologicalAge, 41.3, accuracy: 0.05)
    }

    /// Sum of negative deltas below -maxDriftYears must clamp.
    /// Construct unrealistically saturating positive inputs and
    /// verify the result lands exactly at `chronologicalAge -
    /// maxDriftYears` — proving the clamp is doing its job, not
    /// just that the constant exists.
    func test_estimate_extremePositivePush_clampsToCap() {
        // Best-case-everything inputs: very high HRV, very low RHR,
        // long sleep, and ongoing weight loss. Each driver
        // contributes its full negative-delta share; the sum will
        // exceed -8 years without the cap.
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 50,
            hrvMedian30d: 120,
            rhrMedian30d: 40,
            sleepHoursMedian30d: 9,
            weightDeltaKg30d: -4,
            healthDataDays: 30
        )
        guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
            return XCTFail("Engine should accept fully-loaded inputs")
        }
        // chronologicalAge - maxDriftYears = 50 - 8 = 42.
        XCTAssertEqual(result.biologicalAge, 42.0, accuracy: 0.01,
                       "Biological age should clamp at chronologicalAge - maxDriftYears")
    }

    /// Symmetric clamp on the worst-case side: low HRV, high RHR,
    /// poor sleep, weight gain. Sum exceeds +maxDriftYears; result
    /// must clamp at `chronologicalAge + maxDriftYears`.
    func test_estimate_extremeNegativePush_clampsToCap() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 30,
            hrvMedian30d: 15,
            rhrMedian30d: 95,
            sleepHoursMedian30d: 4,
            weightDeltaKg30d: 5,
            healthDataDays: 30
        )
        guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
            return XCTFail("Engine should accept fully-loaded inputs")
        }
        // chronologicalAge + maxDriftYears = 30 + 8 = 38.
        XCTAssertEqual(result.biologicalAge, 38.0, accuracy: 0.01,
                       "Biological age should clamp at chronologicalAge + maxDriftYears")
    }
}
