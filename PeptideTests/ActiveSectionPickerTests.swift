import XCTest
import SwiftUI
@testable import Peptide

/// `ActiveSectionPicker.pick(from:)` is a pure value-in / value-out
/// helper so the chip-bar's "you are here" logic can be locked
/// down without a SwiftUI host.
final class ActiveSectionPickerTests: XCTestCase {

    // MARK: - Default inset

    /// When no anchor has scrolled past the header inset (everything
    /// is below it), nothing is "active" yet.
    func test_pick_allBelowInset_returnsNil() {
        let frames: [TodayJumpBar.SectionAnchor: CGRect] = [
            .meals:    .init(x: 0, y: 400, width: 300, height: 200),
            .wellness: .init(x: 0, y: 700, width: 300, height: 200),
            .movement: .init(x: 0, y: 1000, width: 300, height: 200),
        ]
        XCTAssertNil(ActiveSectionPicker.pick(from: frames))
    }

    /// Anchor whose top edge is just above the inset wins — even
    /// when later anchors are far below. "Most recently scrolled
    /// past the inset" is the user's reading position.
    func test_pick_oneSectionAtInset_returnsThatSection() {
        let frames: [TodayJumpBar.SectionAnchor: CGRect] = [
            .meals:    .init(x: 0, y: 50,  width: 300, height: 200),   // above inset
            .wellness: .init(x: 0, y: 400, width: 300, height: 200),
            .movement: .init(x: 0, y: 700, width: 300, height: 200),
        ]
        XCTAssertEqual(ActiveSectionPicker.pick(from: frames), .meals)
    }

    /// When two anchors are above the inset, the one with the
    /// larger minY (closer to the inset, more recently scrolled
    /// past) wins.
    func test_pick_multipleAboveInset_picksMostRecent() {
        let frames: [TodayJumpBar.SectionAnchor: CGRect] = [
            .meals:    .init(x: 0, y: -200, width: 300, height: 200),  // scrolled way up
            .doses:    .init(x: 0, y: -20,  width: 300, height: 200),  // just above inset
            .wellness: .init(x: 0, y: 400,  width: 300, height: 200),
        ]
        XCTAssertEqual(ActiveSectionPicker.pick(from: frames), .doses)
    }

    /// Custom inset is honoured — useful for tuning the picker
    /// against different sticky-header heights.
    func test_pick_customInset_changesThreshold() {
        let frames: [TodayJumpBar.SectionAnchor: CGRect] = [
            .meals:    .init(x: 0, y: 80,  width: 300, height: 200),
            .wellness: .init(x: 0, y: 250, width: 300, height: 200),
        ]
        // With inset=100, only meals qualifies.
        XCTAssertEqual(ActiveSectionPicker.pick(from: frames, headerInset: 100), .meals)
        // With inset=300, both qualify; wellness has the larger
        // minY and wins.
        XCTAssertEqual(ActiveSectionPicker.pick(from: frames, headerInset: 300), .wellness)
    }

    func test_pick_emptyInput_returnsNil() {
        XCTAssertNil(ActiveSectionPicker.pick(from: [:]))
    }
}
