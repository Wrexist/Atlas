import XCTest
@testable import Peptide

@MainActor
final class QuickActionTests: XCTestCase {

    func test_everyQuickAction_roundTripsThroughItsDeepLink() throws {
        for action in QuickAction.allCases {
            let state = AppState()
            let url = try XCTUnwrap(action.url)
            XCTAssertTrue(DeepLinkRouter.route(url, appState: state))
            XCTAssertEqual(state.pendingQuickAction, action)
        }
    }

    func test_unknownQuickAction_isRejected() throws {
        let state = AppState()
        let url = try XCTUnwrap(URL(string: "peptidex://quick/teleport"))
        XCTAssertFalse(DeepLinkRouter.route(url, appState: state))
        XCTAssertNil(state.pendingQuickAction)
    }

    func test_waterInbox_drainsInOrderAndEmpties() throws {
        let suite = "QuickActionTests.water"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let later = Date()
        let earlier = later.addingTimeInterval(-60)

        PendingWaterLogStore.enqueue(later, defaults: defaults)
        PendingWaterLogStore.enqueue(earlier, defaults: defaults)

        XCTAssertEqual(PendingWaterLogStore.drain(defaults: defaults), [earlier, later])
        XCTAssertEqual(PendingWaterLogStore.drain(defaults: defaults), [])
    }
}
