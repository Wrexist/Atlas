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
            PerformanceAgeEngine.confidenceScore(coverage: 1, healthDataDays: 6),
            0
        )
    }

    func test_confidenceScore_thirtyDaysFullCoverage_isOne() {
        XCTAssertEqual(
            PerformanceAgeEngine.confidenceScore(coverage: 1, healthDataDays: 30),
            1.0,
            accuracy: 0.001
        )
    }

    /// Halfway up the density curve with three-quarters coverage.
    /// density at 18 days = 0.4 + (11/23)*0.6 ≈ 0.687. Product ≈ 0.515.
    func test_confidenceScore_partialDataAndDays_scales() {
        let score = PerformanceAgeEngine.confidenceScore(coverage: 0.75, healthDataDays: 18)
        XCTAssertEqual(score, 0.515, accuracy: 0.005)
    }

    func test_confidenceScore_outOfRangeCoverage_isClamped() {
        XCTAssertEqual(PerformanceAgeEngine.confidenceScore(coverage: 3, healthDataDays: 30), 1)
        XCTAssertEqual(PerformanceAgeEngine.confidenceScore(coverage: -1, healthDataDays: 30), 0)
    }

    /// HRV + resting HR + sleep + weight — the typical Apple Watch
    /// wearer's set — must still count as complete, as it did before
    /// VO2 max, steps and BMI joined the engine.
    func test_coverage_watchCoreSignals_isComplete() {
        XCTAssertEqual(PerformanceAgeEngine.coverage(of: [.hrv, .rhr, .sleep, .weight]), 1, accuracy: 0.001)
    }

    /// An iPhone-only user (steps, weight, BMI) can't reach the bar: those
    /// signals alone say too little about ageing to commit to a number.
    func test_coverage_phoneOnlySignals_staysBelowMinimum() {
        let coverage = PerformanceAgeEngine.coverage(of: [.steps, .weight, .bodyMassIndex])
        XCTAssertLessThan(
            PerformanceAgeEngine.confidenceScore(coverage: coverage, healthDataDays: 30),
            PerformanceAgeEngine.minConfidence
        )
    }

    func test_coverage_duplicateKinds_countOnce() {
        XCTAssertEqual(
            PerformanceAgeEngine.coverage(of: [.hrv, .hrv, .hrv]),
            PerformanceAgeEngine.coverage(of: [.hrv])
        )
    }

    func test_coverageWeights_sumToOne() {
        let total = PerformanceAgeEngine.Driver.Kind.allCases.reduce(0.0) { $0 + $1.coverageWeight }
        XCTAssertEqual(total, 1, accuracy: 0.0001)
    }

    // MARK: - HRV age adjustment

    /// At or below the reference age the thresholds are the published
    /// constants; past it they slide down, so the same reading reads
    /// younger for an older user.
    func test_hrvContribution_olderUser_readsSameValueYounger() {
        XCTAssertEqual(PerformanceAgeEngine.hrvContribution(hrv: 40, age: 25),
                       PerformanceAgeEngine.hrvContribution(hrv: 40))
        XCTAssertLessThan(PerformanceAgeEngine.hrvContribution(hrv: 40, age: 60),
                          PerformanceAgeEngine.hrvContribution(hrv: 40, age: 30))
    }

    func test_hrvReference_shiftIsBounded() {
        XCTAssertEqual(PerformanceAgeEngine.hrvReference(age: 30), 42.5, accuracy: 0.001)
        XCTAssertEqual(PerformanceAgeEngine.hrvReference(age: 60), 27.5, accuracy: 0.001)
        XCTAssertEqual(PerformanceAgeEngine.hrvReference(age: 95),
                       PerformanceAgeEngine.hrvReference(age: 60),
                       "Shift caps at hrvMaxAgeShift")
    }

    // MARK: - VO2 max

    func test_vo2MaxReference_declinesWithAgeAndDiffersBySex() {
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxReference(age: 25, sex: .male), 44, accuracy: 0.001)
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxReference(age: 25, sex: .female), 37, accuracy: 0.001)
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxReference(age: 25, sex: .unspecified), 40.5, accuracy: 0.001)
        XCTAssertLessThan(PerformanceAgeEngine.vo2MaxReference(age: 60, sex: .male),
                          PerformanceAgeEngine.vo2MaxReference(age: 30, sex: .male))
    }

    func test_vo2MaxContribution_atReference_isNeutral() {
        let reference = PerformanceAgeEngine.vo2MaxReference(age: 45, sex: .female)
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxContribution(vo2Max: reference, age: 45, sex: .female),
                       0, accuracy: 0.001)
    }

    /// 4 ml/kg/min above reference at 2 units per year → 2 years younger.
    func test_vo2MaxContribution_aboveReference_readsYounger() {
        let reference = PerformanceAgeEngine.vo2MaxReference(age: 40, sex: .male)
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxContribution(vo2Max: reference + 4, age: 40, sex: .male),
                       -2, accuracy: 0.001)
    }

    func test_vo2MaxContribution_extremeValues_areBounded() {
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxContribution(vo2Max: 90, age: 40, sex: .male),
                       -PerformanceAgeEngine.vo2SwingYears)
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxContribution(vo2Max: 8, age: 40, sex: .male),
                       PerformanceAgeEngine.vo2SwingYears)
        XCTAssertEqual(PerformanceAgeEngine.vo2MaxContribution(vo2Max: 0, age: 40, sex: .male), 0)
    }

    // MARK: - Steps

    func test_stepsContribution_curveEndsAndMidpoint() {
        XCTAssertEqual(PerformanceAgeEngine.stepsContribution(steps: 2_000), 1.0)
        XCTAssertEqual(PerformanceAgeEngine.stepsContribution(steps: 25_000), -1.0)
        XCTAssertEqual(PerformanceAgeEngine.stepsContribution(steps: 7_000), 0, accuracy: 0.001)
        XCTAssertEqual(PerformanceAgeEngine.stepsContribution(steps: 0), 0)
    }

    // MARK: - BMI

    func test_bmiContribution_healthyRange_isNeutralAndNeverRewards() {
        XCTAssertEqual(PerformanceAgeEngine.bmiContribution(bmi: 18.5), 0)
        XCTAssertEqual(PerformanceAgeEngine.bmiContribution(bmi: 22), 0)
        XCTAssertEqual(PerformanceAgeEngine.bmiContribution(bmi: 27), 0)
    }

    func test_bmiContribution_highAndLow_penaliseWithinBounds() {
        XCTAssertEqual(PerformanceAgeEngine.bmiContribution(bmi: 31), 0.75, accuracy: 0.001)
        XCTAssertEqual(PerformanceAgeEngine.bmiContribution(bmi: 45), PerformanceAgeEngine.bmiHighPenaltyYears)
        XCTAssertEqual(PerformanceAgeEngine.bmiContribution(bmi: 16), PerformanceAgeEngine.bmiUnderweightPenaltyYears)
    }

    func test_bodyMassIndex_computesFromProfile() {
        XCTAssertEqual(PerformanceAgeEngine.bodyMassIndex(weightKg: 80, heightCm: 180) ?? 0, 24.69, accuracy: 0.01)
    }

    /// A height typed in inches, a missing field, or a zero weight must
    /// not turn into a BMI the estimate then penalises.
    func test_bodyMassIndex_missingOrImplausible_returnsNil() {
        XCTAssertNil(PerformanceAgeEngine.bodyMassIndex(weightKg: 80, heightCm: nil))
        XCTAssertNil(PerformanceAgeEngine.bodyMassIndex(weightKg: nil, heightCm: 180))
        XCTAssertNil(PerformanceAgeEngine.bodyMassIndex(weightKg: 80, heightCm: 70))
        XCTAssertNil(PerformanceAgeEngine.bodyMassIndex(weightKg: 0, heightCm: 180))
        XCTAssertNil(PerformanceAgeEngine.bodyMassIndex(weightKg: 400, heightCm: 150))
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

    /// The two tests here used to assert that saturating inputs land
    /// *exactly* on `chronologicalAge ∓ maxDriftYears`, "proving the clamp is
    /// doing its job". They could not: the four drivers sum to at most +6.3
    /// and -4.3, against a ±8 cap, so the clamp is unreachable by
    /// construction. Both failed on the real numbers (46.2 vs 42, 36.3 vs 38)
    /// and the test directly above them already asserts the +6.3 sum lands
    /// unclamped — the suite contradicted itself.
    ///
    /// The cap is a safety belt, not a target: it exists so a future constant
    /// change or a bad input can't age someone a decade. So these now pin the
    /// two things that are actually true and worth defending — what the
    /// extremes reach, and that nothing can escape the belt.

    /// Best-case-everything: very high HRV, very low RHR, long sleep.
    ///
    /// Note the weight input. This test used to pass -4kg believing weight
    /// loss reads as younger; `weightContribution` penalises rapid change in
    /// *either* direction, so -4kg adds +0.5 and the "best case" was scoring
    /// itself worse. Stable weight is the real optimum.
    func test_estimate_bestCaseInputs_reachFullNegativeSwing() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 50,
            hrvMedian30d: 120,
            rhrMedian30d: 40,
            sleepHoursMedian30d: 9,
            weightDeltaKg30d: 0,
            healthDataDays: 30
        )
        guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
            return XCTFail("Engine should accept fully-loaded inputs")
        }
        // -2.5 (HRV) + -1.8 (RHR) + 0 (sleep at target is neutral, never a
        // bonus) + 0 (stable weight) = -4.3.
        XCTAssertEqual(result.biologicalAge, 45.7, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(
            result.biologicalAge,
            50 - PerformanceAgeEngine.maxDriftYears,
            "Nothing may drift past the cap"
        )
    }

    /// Worst-case-everything: low HRV, high RHR, poor sleep, rapid weight gain.
    func test_estimate_worstCaseInputs_reachFullPositiveSwing() {
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
        // +2.5 + 1.8 + 1.5 + 0.5 = +6.3.
        XCTAssertEqual(result.biologicalAge, 36.3, accuracy: 0.01)
        XCTAssertLessThanOrEqual(
            result.biologicalAge,
            30 + PerformanceAgeEngine.maxDriftYears,
            "Nothing may drift past the cap"
        )
    }

    /// The belt itself. Saturating every driver in the same direction is the
    /// most the engine can produce today; if a constant is raised past the
    /// cap later, this is what catches it.
    func test_estimate_saturatedDrivers_stayWithinMaxDrift() {
        for age in [20, 45, 70] {
            for inputs in [
                PerformanceAgeEngine.Inputs(chronologicalAge: age, hrvMedian30d: 200,
                                            rhrMedian30d: 30, sleepHoursMedian30d: 12,
                                            weightDeltaKg30d: 0, healthDataDays: 30),
                PerformanceAgeEngine.Inputs(chronologicalAge: age, hrvMedian30d: 1,
                                            rhrMedian30d: 200, sleepHoursMedian30d: 1,
                                            weightDeltaKg30d: 50, healthDataDays: 30),
            ] {
                guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
                    return XCTFail("Engine should accept fully-loaded inputs")
                }
                XCTAssertLessThanOrEqual(
                    abs(result.biologicalAge - Double(age)),
                    PerformanceAgeEngine.maxDriftYears,
                    "Drift from \(age) exceeded the ±\(PerformanceAgeEngine.maxDriftYears)y cap"
                )
            }
        }
    }

    // MARK: - All signals

    /// Every signal present and favourable: VO2 max well above reference
    /// leads the drivers, nothing is reported missing, and the total
    /// stays inside the cap.
    func test_estimate_allSignals_vo2LeadsAndNoneMissing() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 40,
            sex: .male,
            hrvMedian30d: 70,
            rhrMedian30d: 50,
            sleepHoursMedian30d: 8,
            weightDeltaKg30d: 0.2,
            vo2MaxRecent: 52,
            stepsMedian30d: 11_000,
            bodyMassIndex: 23,
            healthDataDays: 30
        )
        guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
            return XCTFail("Expected estimate")
        }
        XCTAssertEqual(result.drivers.first?.kind, .vo2Max)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertEqual(result.drivers.count, PerformanceAgeEngine.Driver.Kind.allCases.count)
        // -3 (VO2) - 2.5 (HRV) - 1.8 (RHR) - 1 (steps) = -8.3 → capped at -8.
        XCTAssertEqual(result.biologicalAge, 32, accuracy: 0.001)
    }

    /// With seven signals the cap is reachable; it must hold on both sides.
    func test_estimate_allSignalsWorstCase_isCapped() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 50,
            sex: .female,
            hrvMedian30d: 5,
            rhrMedian30d: 95,
            sleepHoursMedian30d: 4,
            weightDeltaKg30d: 6,
            vo2MaxRecent: 12,
            stepsMedian30d: 1_000,
            bodyMassIndex: 42,
            healthDataDays: 30
        )
        guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
            return XCTFail("Expected estimate")
        }
        XCTAssertEqual(result.biologicalAge, 50 + PerformanceAgeEngine.maxDriftYears, accuracy: 0.001)
    }

    /// Drivers carry the reading and its reference so the page can show
    /// "48 ms · typical 41 ms" without recomputing anything.
    func test_estimate_driversCarryValueAndReference() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 30, hrvMedian30d: 48, rhrMedian30d: 60,
            sleepHoursMedian30d: 7, healthDataDays: 30
        )
        guard let hrv = PerformanceAgeEngine.estimate(inputs: inputs)?.drivers.first(where: { $0.kind == .hrv }) else {
            return XCTFail("Expected an HRV driver")
        }
        XCTAssertEqual(hrv.value, 48)
        XCTAssertEqual(hrv.reference ?? 0, 42.5, accuracy: 0.001)
    }

    /// A zero or NaN reading is a broken sample, not a measurement: it must
    /// not be scored, and must not count toward coverage.
    func test_drivers_nonPositiveOrNonFiniteReadings_areMissing() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 30,
            hrvMedian30d: 0,
            rhrMedian30d: .nan,
            sleepHoursMedian30d: -1,
            weightDeltaKg30d: .infinity,
            vo2MaxRecent: 0,
            stepsMedian30d: .nan,
            bodyMassIndex: 0,
            healthDataDays: 30
        )
        XCTAssertTrue(PerformanceAgeEngine.drivers(for: inputs).isEmpty)
        XCTAssertNil(PerformanceAgeEngine.estimate(inputs: inputs))
    }

    /// No HRV, but resting HR, sleep and VO2 max: a watch without HRV
    /// still gets an estimate, and HRV is listed as missing.
    func test_estimate_missingHRV_listsItAsMissing() {
        let inputs = PerformanceAgeEngine.Inputs(
            chronologicalAge: 35, rhrMedian30d: 60, sleepHoursMedian30d: 7.2,
            vo2MaxRecent: 40, healthDataDays: 30
        )
        guard let result = PerformanceAgeEngine.estimate(inputs: inputs) else {
            return XCTFail("Expected estimate")
        }
        XCTAssertTrue(result.missing.contains(.hrv))
        XCTAssertFalse(result.drivers.contains { $0.kind == .hrv })
    }

    // MARK: - From daily series

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func day(_ offset: Int, from end: Date) -> Date {
        utc.date(byAdding: .day, value: offset, to: end) ?? end
    }

    private func series(_ values: [Double], endingOn end: Date) -> [PerformanceAgeEngine.DailyValue] {
        values.enumerated().map { index, value in
            .init(date: day(index - values.count + 1, from: end), value: value)
        }
    }

    /// Medians over the trailing 30 days only; days outside it are ignored
    /// and coverage counts distinct days across HRV, RHR and sleep.
    func test_inputs_asOf_usesTrailingWindowMedians() {
        let end = utc.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        // 40 days of HRV: the oldest 10 are 200 ms and must be ignored.
        let hrv = series(Array(repeating: 200, count: 10) + Array(repeating: 50, count: 30), endingOn: end)
        let input = PerformanceAgeEngine.inputs(
            asOf: end,
            series: .init(
                hrv: hrv,
                rhr: series([60, 62, 58], endingOn: end),
                sleepHours: series([7, 8], endingOn: end),
                steps: series([5_000, 9_000, 7_000], endingOn: end),
                vo2Max: [.init(date: day(-80, from: end), value: 41), .init(date: day(-200, from: end), value: 20)],
                weightKg: [.init(date: day(-40, from: end), value: 90),
                           .init(date: day(-20, from: end), value: 80),
                           .init(date: day(-1, from: end), value: 81.5)]
            ),
            profile: .init(chronologicalAge: 35, sex: .male, bodyMassIndex: 24),
            calendar: utc
        )
        XCTAssertEqual(input.hrvMedian30d, 50)
        XCTAssertEqual(input.rhrMedian30d, 60)
        XCTAssertEqual(input.sleepHoursMedian30d, 7.5)
        XCTAssertEqual(input.stepsMedian30d, 7_000)
        XCTAssertEqual(input.vo2MaxRecent, 41, "VO2 max reads a 90-day window")
        XCTAssertEqual(input.weightDeltaKg30d ?? 0, 1.5, accuracy: 0.001, "Weigh-ins before the window are ignored")
        XCTAssertEqual(input.healthDataDays, 30)
        XCTAssertEqual(input.bodyMassIndex, 24)
        XCTAssertEqual(input.sex, .male)
    }

    func test_inputs_emptySeries_isAllMissing() {
        let input = PerformanceAgeEngine.inputs(
            asOf: Date(), series: .init(), profile: .init(chronologicalAge: 30), calendar: utc
        )
        XCTAssertNil(input.hrvMedian30d)
        XCTAssertNil(input.vo2MaxRecent)
        XCTAssertNil(input.weightDeltaKg30d)
        XCTAssertEqual(input.healthDataDays, 0)
    }

    /// Weekly points over 90 days, oldest first; points before there was
    /// enough data are left out rather than guessed.
    func test_trend_skipsPointsWithoutEnoughData() {
        let end = utc.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        // 40 days of data: only points whose 30-day window has ≥ 7 days count.
        let values = Array(repeating: 55.0, count: 40)
        let points = PerformanceAgeEngine.trend(
            series: .init(hrv: series(values, endingOn: end),
                          rhr: series(Array(repeating: 58, count: 40), endingOn: end),
                          sleepHours: series(Array(repeating: 7.6, count: 40), endingOn: end)),
            profile: .init(chronologicalAge: 30),
            endingOn: end,
            calendar: utc
        )
        XCTAssertFalse(points.isEmpty)
        XCTAssertLessThan(points.count, 90 / 7 + 1)
        XCTAssertEqual(points.last?.date, end)
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }

    func test_trend_noData_isEmpty() {
        XCTAssertTrue(PerformanceAgeEngine.trend(
            series: .init(), profile: .init(chronologicalAge: 30), endingOn: Date(), calendar: utc
        ).isEmpty)
    }

    /// Today's steps bucket is a running total until midnight, so a tiny
    /// morning count must not drag the median down.
    func test_inputs_partialTodaySteps_doNotChangeMedian() {
        let end = utc.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let finished = series([8_000, 8_000, 8_000], endingOn: day(-1, from: end))
        let morning = PerformanceAgeEngine.DailyValue(date: end.addingTimeInterval(8 * 3_600), value: 900)
        let withToday = PerformanceAgeEngine.inputs(
            asOf: end.addingTimeInterval(8 * 3_600),
            series: .init(steps: finished + [morning]),
            profile: .init(chronologicalAge: 30),
            calendar: utc
        )
        XCTAssertEqual(withToday.stepsMedian30d, 8_000)
    }

    // MARK: - Unlock day

    /// Full coverage: 14 days is just below the confidence gate, 15 clears it.
    func test_estimate_fullCoverage_unlocksOnDayFifteen() {
        func inputs(days: Int) -> PerformanceAgeEngine.Inputs {
            .init(chronologicalAge: 35, hrvMedian30d: 50, rhrMedian30d: 60,
                  sleepHoursMedian30d: 7.5, vo2MaxRecent: 40, healthDataDays: days)
        }
        XCTAssertNil(PerformanceAgeEngine.estimate(inputs: inputs(days: 14)))
        XCTAssertNotNil(PerformanceAgeEngine.estimate(inputs: inputs(days: 15)))
        XCTAssertEqual(PerformanceAgeEngine.minimumDays(forCoverage: 1), 15)
    }

    /// The typical watch set (HRV + resting HR + sleep) unlocks later, and
    /// the derived day is exactly where the engine starts answering.
    func test_minimumDays_watchCoreSignals_matchesEstimateGate() throws {
        let coverage = PerformanceAgeEngine.coverage(of: [.hrv, .rhr, .sleep])
        let required = try XCTUnwrap(PerformanceAgeEngine.minimumDays(forCoverage: coverage))
        XCTAssertEqual(required, 17)
        func inputs(days: Int) -> PerformanceAgeEngine.Inputs {
            .init(chronologicalAge: 35, hrvMedian30d: 50, rhrMedian30d: 60,
                  sleepHoursMedian30d: 7.5, healthDataDays: days)
        }
        XCTAssertNil(PerformanceAgeEngine.estimate(inputs: inputs(days: required - 1)))
        XCTAssertNotNil(PerformanceAgeEngine.estimate(inputs: inputs(days: required)))
    }

    /// Coverage too thin to ever clear the gate: more days won't help.
    func test_minimumDays_lowCoverage_isNil() {
        XCTAssertNil(PerformanceAgeEngine.minimumDays(forCoverage: PerformanceAgeEngine.coverage(of: [.steps])))
    }

    func test_median_evenOddAndNonFinite() {
        XCTAssertEqual(PerformanceAgeEngine.median([3, 1, 2]), 2)
        XCTAssertEqual(PerformanceAgeEngine.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(PerformanceAgeEngine.median([.nan, 5]), 5)
        XCTAssertNil(PerformanceAgeEngine.median([]))
    }
}
