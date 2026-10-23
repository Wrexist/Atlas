import XCTest
@testable import Peptide

/// The UI test target cannot import the app, so its launch arguments carry
/// the What's New tour stamp as a literal. If it falls behind a bump of
/// `currentTourVersion`, the full-screen tour sheet appears in every UI
/// test and absorbs the tab taps. Reads the helper's source to catch that.
@MainActor
final class WhatsNewTourStampTests: XCTestCase {
    func test_uiTestTourStamp_matchesCurrentTourVersion() throws {
        let helper = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "PeptideUITests/XCUIApplication+Atlas.swift")
        let source = try String(contentsOf: helper, encoding: .utf8)
        XCTAssertTrue(
            source.contains("\"\(WhatsNewService.currentTourVersion)\""),
            "Update the lastSeenVersion stamp in XCUIApplication+Atlas.swift to \(WhatsNewService.currentTourVersion)"
        )
    }
}
