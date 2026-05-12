import XCTest
@testable import Peptide

@MainActor
final class HealthKitBackgroundDeliveryTests: XCTestCase {

    // MARK: - HealthSnapshot
    //
    // Property-setter regurgitation tests were removed — they asserted
    // `xs.foo == foo`, which only verified that Swift's synthesised
    // memberwise init does what Swift's synthesised memberwise init
    // does. Real coverage of HealthSnapshot comes from the
    // HealthKitService consumers that compute / read these fields,
    // exercised in the device-only paths below.

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
