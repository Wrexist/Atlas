import XCTest
@testable import Peptide

@MainActor
final class AppStateTests: XCTestCase {

    func test_defaults_homeTab_andNoPendingDeepLink() {
        let state = AppState()
        XCTAssertEqual(state.selectedTab, .home)
        XCTAssertNil(state.pendingProtocolDeepLink)
    }

    func test_pendingProtocolDeepLink_canBeSetAndCleared() {
        let state = AppState()
        let id = UUID()

        state.pendingProtocolDeepLink = id
        XCTAssertEqual(state.pendingProtocolDeepLink, id)

        // The view that consumes the deep link is responsible for clearing it
        // after pushing onto its navigation path so re-tapping the same row
        // navigates again.
        state.pendingProtocolDeepLink = nil
        XCTAssertNil(state.pendingProtocolDeepLink)
    }

    func test_selectedTab_canBeSetIndependentlyOfDeepLink() {
        let state = AppState()
        state.selectedTab = .protocols
        XCTAssertEqual(state.selectedTab, .protocols)
        XCTAssertNil(state.pendingProtocolDeepLink)
    }
}
