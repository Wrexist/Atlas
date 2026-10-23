import XCTest
@testable import Peptide

@MainActor
final class LabEntryEditorTests: XCTestCase {

    func test_parseDecimal_infinityOrOverflow_isRejected() {
        XCTAssertNil(LabEntryEditor.parseDecimal("inf"))
        XCTAssertNil(LabEntryEditor.parseDecimal("1e999"))
        XCTAssertNil(LabEntryEditor.parseDecimal("nan"))
    }

    func test_parseDecimal_plainNumber_parses() {
        XCTAssertEqual(LabEntryEditor.parseDecimal(" 720 "), 720)
    }

    func test_parseDecimal_empty_isNil() {
        XCTAssertNil(LabEntryEditor.parseDecimal("   "))
    }
}
