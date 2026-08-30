import XCTest
@testable import Peptide

/// Pins the `peptidex://` URL vocabulary. Every widget, Live Activity,
/// and notification deep link funnels through `DeepLinkRouter.route`,
/// so a renamed host or a dropped case breaks a shipped tap target —
/// these tests make that a compile-time-adjacent failure instead of a
/// silent dead link discovered on a device.
@MainActor
final class DeepLinkRouterTests: XCTestCase {

    private func route(_ string: String) -> (handled: Bool, state: AppState) {
        let state = AppState()
        let handled = DeepLinkRouter.route(XCTUnwrapURL(string), appState: state)
        return (handled, state)
    }

    private func XCTUnwrapURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            XCTFail("Invalid test URL: \(string)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    func test_doseHost_parksEntryIdAndSelectsToday() {
        let id = UUID()
        let (handled, state) = route("peptidex://dose/\(id.uuidString)")
        XCTAssertTrue(handled)
        XCTAssertEqual(state.selectedTab, .today)
        XCTAssertEqual(state.pendingDoseLogEntryId, id)
    }

    func test_doseHost_rejectsGarbledUUID_withoutMutatingState() {
        let (handled, state) = route("peptidex://dose/not-a-uuid")
        XCTAssertFalse(handled)
        XCTAssertNil(state.pendingDoseLogEntryId)
        XCTAssertEqual(state.selectedTab, .today) // default, untouched
    }

    func test_weeklyHost_flagsRecapAndSelectsToday() {
        let (handled, state) = route("peptidex://weekly/current")
        XCTAssertTrue(handled)
        XCTAssertEqual(state.selectedTab, .today)
        XCTAssertTrue(state.pendingWeeklyRecap)
    }

    func test_tabHosts_selectTheirTabs() {
        XCTAssertEqual(route("peptidex://today").state.selectedTab, .today)
        XCTAssertEqual(route("peptidex://train").state.selectedTab, .train)
        XCTAssertEqual(route("peptidex://meals").state.selectedTab, .meals)
        XCTAssertTrue(route("peptidex://train").handled)
    }

    func test_unknownHost_isIgnored() {
        let (handled, state) = route("peptidex://nonsense/path")
        XCTAssertFalse(handled)
        XCTAssertFalse(state.pendingWeeklyRecap)
        XCTAssertNil(state.pendingDoseLogEntryId)
    }

    func test_foreignScheme_isIgnored() {
        let (handled, state) = route("https://example.com/dose/\(UUID().uuidString)")
        XCTAssertFalse(handled)
        XCTAssertNil(state.pendingDoseLogEntryId)
    }
}
