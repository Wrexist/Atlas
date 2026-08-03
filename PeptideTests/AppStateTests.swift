import XCTest
@testable import Peptide

@MainActor
final class AppStateTests: XCTestCase {

    func test_defaults_todayTab_andNoPendingDeepLink() {
        let state = AppState()
        XCTAssertEqual(state.selectedTab, .today)
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
        state.selectedTab = .train
        XCTAssertEqual(state.selectedTab, .train)
        XCTAssertNil(state.pendingProtocolDeepLink)
    }

    /// Protocols lost its tab slot when Habits was promoted — it reaches
    /// the user as a modal over whatever tab they are on. This test used
    /// to assert `selectedTab = .protocols`, which is what stopped the
    /// whole test target compiling.
    func test_library_opensOverTheCurrentTabRatherThanSwitchingToIt() {
        let state = AppState()
        state.pendingProtocolList = true
        state.showLibrary = true

        XCTAssertTrue(state.showLibrary)
        XCTAssertTrue(state.pendingProtocolList)
        XCTAssertEqual(state.selectedTab, .today,
                       "Opening Library must not move the user off their tab")
    }
}
