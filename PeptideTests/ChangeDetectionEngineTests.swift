import XCTest
@testable import Peptide

final class ChangeDetectionEngineTests: XCTestCase {

    private func baseline(
        mean: Double,
        standardDeviation: Double,
        p10: Double,
        p90: Double,
        confidence: BaselineConfidence = .establishedBaseline
    ) -> PersonalBaselineEngine.Baseline {
        PersonalBaselineEngine.Baseline(
            mean: mean,
            median: mean,
            standardDeviation: standardDeviation,
            p10: p10,
            p25: mean - standardDeviation / 2,
            p75: mean + standardDeviation / 2,
            p90: p90,
            sampleCount: 21,
            confidence: confidence
        )
    }

    func test_evaluate_belowInsufficientConfidence_returnsNil() {
        let insufficient = baseline(mean: 50, standardDeviation: 5, p10: 40, p90: 60, confidence: .insufficientHistory)
        XCTAssertNil(ChangeDetectionEngine.evaluate(current: 50, against: insufficient))
    }

    func test_evaluate_valueNearMean_isStable() {
        let base = baseline(mean: 50, standardDeviation: 5, p10: 40, p90: 60)
        let result = ChangeDetectionEngine.evaluate(current: 51, against: base)
        XCTAssertEqual(result?.change, .stable)
        XCTAssertEqual(result?.confidence, .establishedBaseline)
    }

    func test_evaluate_oneStandardDeviationAbove_isNotablyHigher() {
        let base = baseline(mean: 50, standardDeviation: 5, p10: 30, p90: 70)
        let result = ChangeDetectionEngine.evaluate(current: 55, against: base)
        XCTAssertEqual(result?.change, .notablyHigher)
    }

    func test_evaluate_oneStandardDeviationBelow_isNotablyLower() {
        let base = baseline(mean: 50, standardDeviation: 5, p10: 30, p90: 70)
        let result = ChangeDetectionEngine.evaluate(current: 45, against: base)
        XCTAssertEqual(result?.change, .notablyLower)
    }

    func test_evaluate_aboveP90_isUnusualRegardlessOfStandardDeviationMath() {
        let base = baseline(mean: 50, standardDeviation: 5, p10: 40, p90: 60)
        let result = ChangeDetectionEngine.evaluate(current: 61, against: base)
        XCTAssertEqual(result?.change, .unusual)
    }

    func test_evaluate_belowP10_isUnusual() {
        let base = baseline(mean: 50, standardDeviation: 5, p10: 40, p90: 60)
        let result = ChangeDetectionEngine.evaluate(current: 39, against: base)
        XCTAssertEqual(result?.change, .unusual)
    }

    func test_evaluate_zeroStandardDeviation_valueInsideBand_isStable() {
        // Every historical value identical (stdev 0); a current value that
        // still falls inside the (necessarily single-point) p10-p90 band
        // must not divide-by-zero and must read as stable.
        let base = baseline(mean: 50, standardDeviation: 0, p10: 50, p90: 50)
        let result = ChangeDetectionEngine.evaluate(current: 50, against: base)
        XCTAssertEqual(result?.change, .stable)
    }

    func test_evaluate_zeroStandardDeviation_valueOutsideBand_isUnusual() {
        let base = baseline(mean: 50, standardDeviation: 0, p10: 50, p90: 50)
        let result = ChangeDetectionEngine.evaluate(current: 60, against: base)
        XCTAssertEqual(result?.change, .unusual)
    }

    func test_evaluate_emergingConfidence_stillProducesAVerdict() {
        // Only `.insufficientHistory` is refused — `.emergingBaseline`
        // still gets a (hedgeable-by-the-caller) verdict.
        let base = baseline(mean: 50, standardDeviation: 5, p10: 40, p90: 60, confidence: .emergingBaseline)
        let result = ChangeDetectionEngine.evaluate(current: 50, against: base)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.confidence, .emergingBaseline)
    }

    func test_evaluate_customThreshold_changesSensitivity() {
        let base = baseline(mean: 50, standardDeviation: 5, p10: 20, p90: 80)
        // 1 SD above the mean would normally be notablyHigher, but with a
        // stricter 2-SD threshold it should read as stable instead.
        let result = ChangeDetectionEngine.evaluate(
            current: 55,
            against: base,
            minMeaningfulDeltaInStandardDeviations: 2.0
        )
        XCTAssertEqual(result?.change, .stable)
    }
}
