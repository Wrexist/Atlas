import XCTest
@testable import Peptide

@MainActor
final class HealthKitBackgroundDeliveryTests: XCTestCase {

    // MARK: - HealthSnapshot

    func test_healthSnapshot_storesAllFields() {
        let capturedAt = Date()
        let snapshot = HealthSnapshot(
            heartRate: 65.0,
            restingHeartRate: 58.0,
            hrv: 42.5,
            weight: 80.0,
            steps: 8500.0,
            sleep: 7.5,
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.heartRate, 65.0)
        XCTAssertEqual(snapshot.restingHeartRate, 58.0)
        XCTAssertEqual(snapshot.hrv, 42.5)
        XCTAssertEqual(snapshot.weight, 80.0)
        XCTAssertEqual(snapshot.steps, 8500.0)
        XCTAssertEqual(snapshot.sleep, 7.5)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
    }

    func test_healthSnapshot_allowsNilFields() {
        let snapshot = HealthSnapshot(
            heartRate: nil,
            restingHeartRate: nil,
            hrv: nil,
            weight: nil,
            steps: nil,
            sleep: nil,
            capturedAt: Date()
        )

        XCTAssertNil(snapshot.heartRate)
        XCTAssertNil(snapshot.hrv)
        XCTAssertNil(snapshot.sleep)
    }

    // MARK: - HealthKitService on Simulator

    func test_startBackgroundDelivery_whenUnavailable_completesWithoutCrash() async {
        // HealthKit is unavailable on the simulator — the method must return silently
        // without throwing or crashing. On a real device this is a functional no-op.
        guard !HealthKitService.shared.isAvailable else { return }
        await HealthKitService.shared.startBackgroundDelivery()
        // Reaching here without crashing is the pass condition
    }

    func test_refreshSnapshot_whenUnavailable_leavesSnapshotNil() async {
        guard !HealthKitService.shared.isAvailable else { return }
        await HealthKitService.shared.refreshSnapshot()
        XCTAssertNil(HealthKitService.shared.cachedSnapshot)
    }
}
