import XCTest
@testable import Peptide

/// `HealthRangeService.build()` is HealthKit-bound and hard to test
/// in isolation, but the percentile + sample-from-series helpers
/// are pure and where the actual logic lives. Lock those down here.
///
/// `@MainActor` because `HealthRangeService` is a `@MainActor enum`; without
/// it every call below is a Swift 6 actor-isolation error, which is part of
/// why the test target stopped compiling.
@MainActor
final class HealthRangeServiceTests: XCTestCase {

    // MARK: - percentile

    func test_percentile_returnsExpectedRanks() {
        let sorted = [10.0, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        // Nearest-rank: ceil(p × N) gives the index.
        XCTAssertEqual(HealthRangeService.percentile(sorted, 0.10), 10)
        XCTAssertEqual(HealthRangeService.percentile(sorted, 0.25), 30)
        XCTAssertEqual(HealthRangeService.percentile(sorted, 0.50), 50)
        XCTAssertEqual(HealthRangeService.percentile(sorted, 0.75), 80)
        XCTAssertEqual(HealthRangeService.percentile(sorted, 0.90), 90)
    }

    func test_percentile_emptySeries_returnsZero() {
        XCTAssertEqual(HealthRangeService.percentile([], 0.5), 0)
    }

    func test_percentile_clampsBelowZeroRank_toFirstValue() {
        // p = 0 would compute rank 0, but the helper clamps to the
        // first sample so degenerate inputs degrade gracefully.
        XCTAssertEqual(HealthRangeService.percentile([42.0], 0.0), 42)
    }

    // MARK: - sample(from:direction:)

    func test_sample_belowMinCount_returnsNil() {
        // 6 samples is one below the 7-day floor.
        let series: [(date: Date, value: Double)] = (0..<6).map { i in
            (date: Date(timeIntervalSince1970: TimeInterval(i * 86_400)), value: Double(i))
        }
        XCTAssertNil(HealthRangeService.sample(from: series, direction: .higherIsBetter))
    }

    func test_sample_picksLatestByDate_notLastInArray() {
        // Out-of-order input — the latest by date should win even
        // when it's not the last entry in the array. Mistaking
        // array-order for chronological order would mis-render the
        // range indicator on a series HealthKit returned unsorted.
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let series: [(date: Date, value: Double)] = [
            (baseline.addingTimeInterval( 5 * 86_400), 80),
            (baseline.addingTimeInterval(10 * 86_400), 95),    // most recent
            (baseline.addingTimeInterval( 1 * 86_400), 40),
            (baseline.addingTimeInterval( 2 * 86_400), 50),
            (baseline.addingTimeInterval( 3 * 86_400), 60),
            (baseline.addingTimeInterval( 4 * 86_400), 70),
            (baseline.addingTimeInterval( 6 * 86_400), 75),
        ]
        let sample = HealthRangeService.sample(from: series, direction: .higherIsBetter)
        XCTAssertEqual(sample?.latest, 95)
    }

    func test_sample_statusAndPosition_inferFromQuartiles() {
        // 10 days of data, latest is well above p75 → status .higher,
        // position near top of the range.
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let values: [Double] = [40, 42, 45, 48, 50, 52, 55, 58, 60, 90]   // last day spikes
        let series = values.enumerated().map { i, v in
            (date: baseline.addingTimeInterval(TimeInterval(i * 86_400)), value: v)
        }
        let sample = HealthRangeService.sample(from: series, direction: .higherIsBetter)
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.status, .higher)
        XCTAssertGreaterThan(sample?.positionInRange ?? 0, 0.5)
    }

    func test_sample_positionInRange_clampsOutOfBand() {
        // Latest value below p10 → fraction floors at 0.
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let values: [Double] = [40, 42, 45, 48, 50, 52, 55, 58, 60, 5]   // last day craters
        let series = values.enumerated().map { i, v in
            (date: baseline.addingTimeInterval(TimeInterval(i * 86_400)), value: v)
        }
        let sample = HealthRangeService.sample(from: series, direction: .higherIsBetter)
        XCTAssertEqual(sample?.positionInRange, 0)
        XCTAssertEqual(sample?.status, .lower)
    }

    // MARK: - confidence (personalization brief Phase 3)

    private func series(count: Int) -> [(date: Date, value: Double)] {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { i in
            (date: baseline.addingTimeInterval(TimeInterval(i * 86_400)), value: Double(40 + i))
        }
    }

    func test_sample_atMinCount_hasEmergingConfidence() {
        // Exactly the 7-day floor: enough to render, not enough to call
        // "established" — the whole point of a middle tier.
        let sample = HealthRangeService.sample(from: series(count: 7), direction: .higherIsBetter)
        XCTAssertEqual(sample?.confidence, .emergingBaseline)
        XCTAssertEqual(sample?.confidenceCaption, "Early read — still learning your range")
    }

    func test_sample_atFullWindow_hasEstablishedConfidence() {
        // The full 21-day target window — nothing left to hedge.
        let sample = HealthRangeService.sample(from: series(count: 21), direction: .higherIsBetter)
        XCTAssertEqual(sample?.confidence, .establishedBaseline)
        XCTAssertNil(sample?.confidenceCaption)
    }

    func test_sample_midWindow_stillEmerging() {
        // Between the floor and the full window — still emerging, not
        // yet established.
        let sample = HealthRangeService.sample(from: series(count: 14), direction: .higherIsBetter)
        XCTAssertEqual(sample?.confidence, .emergingBaseline)
    }

    func test_confidenceCaption_defaultConstructedSample_hasNoCaption() {
        // Existing call sites (previews, other tests) that construct a
        // `Sample` directly without specifying `confidence` keep getting
        // the established default and no caption — this is what keeps
        // them source-compatible.
        let sample = HealthRangeService.Sample(
            latest: 58, p10: 35, p25: 42, p75: 60, p90: 70, direction: .higherIsBetter
        )
        XCTAssertEqual(sample.confidence, .establishedBaseline)
        XCTAssertNil(sample.confidenceCaption)
    }
}
