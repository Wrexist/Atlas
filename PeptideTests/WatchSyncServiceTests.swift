import XCTest
@testable import Peptide

/// A Watch command can arrive twice (live send, then the `transferUserInfo`
/// fallback) and hours after the tap. These pin that each id is applied
/// once and that a tap is never logged in the future.
@MainActor
final class WatchSyncServiceTests: XCTestCase {

    private var service: WatchSyncService!
    private var savedLog: UserDefaults!
    private var savedOnMarkComplete: ((UUID, UUID, Date) -> Void)?
    private var savedOnLogWater: ((Double, Date) -> Void)?

    override func setUp() {
        super.setUp()
        service = WatchSyncService.shared
        savedLog = service.deliveryLog
        savedOnMarkComplete = service.onMarkComplete
        savedOnLogWater = service.onLogWater
        let suite = "WatchSyncServiceTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        service.deliveryLog = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        service.deliveryLog = savedLog
        service.onMarkComplete = savedOnMarkComplete
        service.onLogWater = savedOnLogWater
        service = nil
        super.tearDown()
    }

    func test_isFirstDelivery_sameID_secondCallReturnsFalse() {
        XCTAssertTrue(service.isFirstDelivery("a"))
        XCTAssertFalse(service.isFirstDelivery("a"))
    }

    func test_isFirstDelivery_nilID_alwaysTrue() {
        XCTAssertTrue(service.isFirstDelivery(nil))
        XCTAssertTrue(service.isFirstDelivery(nil))
    }

    func test_isFirstDelivery_keepsOnlyLast50IDs() {
        for index in 0...50 {
            XCTAssertTrue(service.isFirstDelivery("id-\(index)"))
        }
        XCTAssertTrue(service.isFirstDelivery("id-0"), "the oldest id fell out of the 50-id window")
        XCTAssertFalse(service.isFirstDelivery("id-50"), "the newest id is still remembered")
    }

    func test_handleWaterMessage_futureIssuedAt_isClampedToNow() {
        var logged: Date?
        service.onLogWater = { _, date in logged = date }
        let before = Date()

        service.handleWaterMessage(fluidOunces: 8, issuedAt: before.addingTimeInterval(3_600), messageID: nil)

        guard let logged else { return XCTFail("the water tap was not logged") }
        XCTAssertLessThanOrEqual(logged, Date())
        XCTAssertGreaterThanOrEqual(logged, before)
    }

    func test_handleWaterMessage_pastIssuedAt_keepsTapTime() {
        var logged: Date?
        service.onLogWater = { _, date in logged = date }
        let tap = Date().addingTimeInterval(-7_200)

        service.handleWaterMessage(fluidOunces: 8, issuedAt: tap, messageID: nil)

        XCTAssertEqual(logged, tap)
    }

    func test_handleWatchMessage_duplicateMarkComplete_callsHandlerOnce() {
        var calls = 0
        service.onMarkComplete = { _, _, _ in calls += 1 }
        let entryId = UUID()
        let protocolId = UUID()

        for _ in 0..<2 {
            service.handleWatchMessage(
                action: WatchMessage.markComplete, entryId: entryId, protocolId: protocolId,
                issuedAt: nil, messageID: "dose-1"
            )
        }

        XCTAssertEqual(calls, 1)
    }
}
