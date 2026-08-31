import XCTest
@testable import Peptide

/// Pure enum, no actor isolation needed.
final class BaselineConfidenceTests: XCTestCase {

    func test_evaluate_belowEmergingThreshold_isInsufficient() {
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 0, emergingAt: 7, establishedAt: 21),
            .insufficientHistory
        )
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 6, emergingAt: 7, establishedAt: 21),
            .insufficientHistory
        )
    }

    func test_evaluate_atEmergingThreshold_isEmerging() {
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 7, emergingAt: 7, establishedAt: 21),
            .emergingBaseline
        )
    }

    func test_evaluate_justBelowEstablishedThreshold_isStillEmerging() {
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 20, emergingAt: 7, establishedAt: 21),
            .emergingBaseline
        )
    }

    func test_evaluate_atEstablishedThreshold_isEstablished() {
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 21, emergingAt: 7, establishedAt: 21),
            .establishedBaseline
        )
    }

    func test_evaluate_wellAboveEstablishedThreshold_isEstablished() {
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 500, emergingAt: 7, establishedAt: 21),
            .establishedBaseline
        )
    }

    func test_evaluate_equalEmergingAndEstablishedThresholds_skipsEmergingTier() {
        // A caller whose domain has no meaningful middle ground (emergingAt
        // == establishedAt) should jump straight from insufficient to
        // established — never getting stuck reporting emerging forever.
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 4, emergingAt: 5, establishedAt: 5),
            .insufficientHistory
        )
        XCTAssertEqual(
            BaselineConfidence.evaluate(sampleCount: 5, emergingAt: 5, establishedAt: 5),
            .establishedBaseline
        )
    }

    // MARK: - Comparable

    func test_comparable_ordersInsufficientLowestAndEstablishedHighest() {
        XCTAssertLessThan(BaselineConfidence.insufficientHistory, .emergingBaseline)
        XCTAssertLessThan(BaselineConfidence.emergingBaseline, .establishedBaseline)
        XCTAssertLessThan(BaselineConfidence.insufficientHistory, .establishedBaseline)
        XCTAssertFalse(BaselineConfidence.establishedBaseline < .insufficientHistory)
    }
}
