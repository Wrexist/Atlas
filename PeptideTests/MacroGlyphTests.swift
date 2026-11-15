import SwiftUI
import XCTest
@testable import Peptide

@MainActor
final class MacroGlyphTests: XCTestCase {
    func test_eachGlyph_fillsItsFrameWithoutSpillingOver() {
        let frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        for kind in MacroKind.allCases {
            let bounds = MacroGlyph(kind: kind).path(in: frame).boundingRect
            XCTAssertGreaterThan(bounds.width, 24, "\(kind) is too small")
            XCTAssertGreaterThan(bounds.height, 24, "\(kind) is too small")
            XCTAssertTrue(frame.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(kind) spills out: \(bounds)")
        }
    }

    func test_wideFrame_centresTheGlyph() {
        let bounds = MacroGlyph(kind: .fat).path(in: CGRect(x: 0, y: 0, width: 96, height: 24)).boundingRect
        XCTAssertEqual(bounds.midX, 48, accuracy: 1)
    }

    func test_avocadoPit_isCutOut() {
        let path = MacroGlyph(kind: .fat).path(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        XCTAssertFalse(path.contains(CGPoint(x: 12, y: 15.2)))
        XCTAssertTrue(path.contains(CGPoint(x: 12, y: 9)))
    }
}
