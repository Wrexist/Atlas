import XCTest
@testable import Peptide

final class HeroMetricSnapshotTests: XCTestCase {

    func test_build_noDosesScheduled_leavesAdherenceUnavailable() async {
        let snapshot = await HeroMetricSnapshot.build(adherenceRatio: nil, healthConnected: false)
        XCTAssertFalse(snapshot.adherence.isAvailable)
        XCTAssertEqual(snapshot.adherence.accessibilityLabel(for: .adherence), "Adherence, no doses today")
    }

    func test_build_noneTakenOfScheduled_showsZeroPercent() async {
        let snapshot = await HeroMetricSnapshot.build(adherenceRatio: 0, healthConnected: false)
        XCTAssertTrue(snapshot.adherence.isAvailable)
        XCTAssertEqual(snapshot.adherence.displayPercent, 0)
    }
}
