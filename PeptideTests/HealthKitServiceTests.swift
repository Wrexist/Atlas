import XCTest
@testable import Peptide

@MainActor
final class HealthKitServiceTests: XCTestCase {

    // HealthKit is unavailable on the simulator, so every accessor must
    // degrade to "no data" rather than throwing or hanging. These are the
    // paths the app hits on a device where the user denied the grant, so
    // the simulator run is real coverage, not a placeholder.

    func test_accessors_whenHealthKitUnavailable_returnNoData() async {
        let service = HealthKitService.shared
        guard !service.isAvailable else { return }

        let hrv = await service.averageHRV(days: 7)
        let rhr = await service.averageRestingHeartRate(days: 7)
        let steps = await service.averageSteps(days: 7)
        let sleep = await service.averageSleepHours(days: 7)

        XCTAssertNil(hrv)
        XCTAssertNil(rhr)
        XCTAssertNil(steps)
        XCTAssertNil(sleep)
    }

    func test_dailySeries_whenHealthKitUnavailable_areEmpty() async {
        let service = HealthKitService.shared
        guard !service.isAvailable else { return }

        let hrv = await service.dailyHRV(days: 30)
        let rhr = await service.dailyRestingHeartRate(days: 30)
        let sleep = await service.dailySleepHours(days: 30)

        XCTAssertTrue(hrv.isEmpty)
        XCTAssertTrue(rhr.isEmpty)
        XCTAssertTrue(sleep.isEmpty)
    }

    func test_authorization_whenHealthKitUnavailable_isDenied() async {
        let service = HealthKitService.shared
        guard !service.isAvailable else { return }

        let read = await service.requestAuthorization()
        let write = await service.requestNutritionWriteAuthorization()

        XCTAssertFalse(read)
        XCTAssertFalse(write)
    }
}
