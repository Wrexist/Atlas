import XCTest
@testable import Peptide

final class PersonalBaselineEngineTests: XCTestCase {

    // MARK: - build(values:emergingAt:establishedAt:)

    func test_build_emptyValues_returnsNil() {
        XCTAssertNil(PersonalBaselineEngine.build(values: [], emergingAt: 3, establishedAt: 6))
    }

    func test_build_singleValue_returnsLowConfidenceBaseline_notNil() {
        // A single data point is "measured once," not "never measured" —
        // the engine must distinguish those, per its own doc comment.
        let baseline = PersonalBaselineEngine.build(values: [50], emergingAt: 3, establishedAt: 6)
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.sampleCount, 1)
        XCTAssertEqual(baseline?.mean, 50)
        XCTAssertEqual(baseline?.median, 50)
        XCTAssertEqual(baseline?.standardDeviation, 0)
        XCTAssertEqual(baseline?.confidence, .insufficientHistory)
    }

    func test_build_computesMeanMedianAndStandardDeviation() {
        let values: [Double] = [2, 4, 4, 4, 5, 5, 7, 9]
        let baseline = PersonalBaselineEngine.build(values: values, emergingAt: 3, establishedAt: 6)
        XCTAssertEqual(baseline?.mean, 5, accuracy: 0.0001)
        // Population standard deviation of this classic example is 2.
        XCTAssertEqual(baseline?.standardDeviation ?? 0, 2, accuracy: 0.0001)
    }

    func test_build_identicalValues_hasZeroStandardDeviation() {
        let baseline = PersonalBaselineEngine.build(values: [10, 10, 10, 10], emergingAt: 2, establishedAt: 4)
        XCTAssertEqual(baseline?.standardDeviation, 0)
        XCTAssertEqual(baseline?.p10, 10)
        XCTAssertEqual(baseline?.p90, 10)
    }

    func test_build_confidenceTiersMatchSampleCount() {
        XCTAssertEqual(
            PersonalBaselineEngine.build(values: [1, 2], emergingAt: 3, establishedAt: 6)?.confidence,
            .insufficientHistory
        )
        XCTAssertEqual(
            PersonalBaselineEngine.build(values: [1, 2, 3], emergingAt: 3, establishedAt: 6)?.confidence,
            .emergingBaseline
        )
        XCTAssertEqual(
            PersonalBaselineEngine.build(values: [1, 2, 3, 4, 5, 6], emergingAt: 3, establishedAt: 6)?.confidence,
            .establishedBaseline
        )
    }

    func test_build_percentilesMatchSortedInput_regardlessOfInputOrder() {
        let shuffled: [Double] = [90, 10, 50, 30, 70, 20, 40, 60, 80, 100]
        let baseline = PersonalBaselineEngine.build(values: shuffled, emergingAt: 1, establishedAt: 1)
        XCTAssertEqual(baseline?.p10, 10)
        XCTAssertEqual(baseline?.p25, 30)
        XCTAssertEqual(baseline?.p75, 80)
        XCTAssertEqual(baseline?.p90, 90)
    }

    // MARK: - percentile(_:_:)

    func test_percentile_matchesNearestRankFormula() {
        let sorted = [10.0, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        XCTAssertEqual(PersonalBaselineEngine.percentile(sorted, 0.10), 10)
        XCTAssertEqual(PersonalBaselineEngine.percentile(sorted, 0.50), 50)
        XCTAssertEqual(PersonalBaselineEngine.percentile(sorted, 0.90), 90)
    }

    func test_percentile_emptyInput_returnsZero() {
        XCTAssertEqual(PersonalBaselineEngine.percentile([], 0.5), 0)
    }

    func test_percentile_singleValue_returnsThatValueAtAnyPercentile() {
        XCTAssertEqual(PersonalBaselineEngine.percentile([42], 0.0), 42)
        XCTAssertEqual(PersonalBaselineEngine.percentile([42], 1.0), 42)
    }
}
