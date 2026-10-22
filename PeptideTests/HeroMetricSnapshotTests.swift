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

    func test_withAdherence_doseToggled_keepsHealthMetrics() {
        let snapshot = HeroMetricSnapshot(
            adherence: .percent(0.5),
            recovery: .percent(0.8),
            sleep: .percent(0.9),
            healthConnected: true,
            recoveryComponents: nil,
            lastSleepHours: 7.2
        )

        let updated = snapshot.withAdherence(1)

        XCTAssertEqual(updated.adherence.displayPercent, 100)
        XCTAssertEqual(updated.recovery, snapshot.recovery)
        XCTAssertEqual(updated.sleep, snapshot.sleep)
        XCTAssertEqual(updated.lastSleepHours, 7.2)
        XCTAssertTrue(updated.healthConnected)
    }

    func test_withAdherence_noDosesScheduled_leavesAdherenceUnavailable() {
        let updated = HeroMetricSnapshot.empty.withAdherence(nil)
        XCTAssertFalse(updated.adherence.isAvailable)
    }
}
