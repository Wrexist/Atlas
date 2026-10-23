import XCTest
@testable import Peptide

/// Pins the shared macro-field validation both meal editors use.
final class MacroInputTests: XCTestCase {

    func test_parse_wholeNumberInRange_returnsValue() {
        XCTAssertEqual(MacroInput.parse(" 450 "), 450)
        XCTAssertEqual(MacroInput.parse("0"), 0)
        XCTAssertEqual(MacroInput.parse("100000"), 100_000)
    }

    func test_parse_outOfRange_returnsNil() {
        XCTAssertNil(MacroInput.parse("200000"))
        XCTAssertNil(MacroInput.parse("-1"))
    }

    func test_parse_blankOrNotWholeNumber_returnsNil() {
        XCTAssertNil(MacroInput.parse(""))
        XCTAssertNil(MacroInput.parse("12.5"))
        XCTAssertNil(MacroInput.parse("abc"))
    }
}
