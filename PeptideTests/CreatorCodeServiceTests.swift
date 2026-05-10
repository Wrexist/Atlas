import XCTest
@testable import Peptide

final class CreatorCodeServiceTests: XCTestCase {

    func test_lookup_exactMatch_returnsAttribution() {
        let result = CreatorCodeService.lookup("LUCAS50")
        XCTAssertEqual(result?.code, "LUCAS50")
        XCTAssertEqual(result?.creatorName, "Lucas Aoun")
        XCTAssertEqual(result?.discountPercent, 20)
    }

    /// Real-world keystrokes are mixed-case; the lookup must normalise.
    func test_lookup_isCaseInsensitive() {
        XCTAssertNotNil(CreatorCodeService.lookup("lucas50"))
        XCTAssertNotNil(CreatorCodeService.lookup("Lucas50"))
        XCTAssertNotNil(CreatorCodeService.lookup("nIDDam"))
    }

    /// Pasting from a chat almost always brings whitespace; tolerate it
    /// instead of forcing the user to clean up before tapping Apply.
    func test_lookup_trimsWhitespace() {
        XCTAssertNotNil(CreatorCodeService.lookup("  BIOHACK  "))
        XCTAssertNotNil(CreatorCodeService.lookup("\nLUCAS50\n"))
    }

    func test_lookup_unknownCode_returnsNil() {
        XCTAssertNil(CreatorCodeService.lookup("WRONG"))
        XCTAssertNil(CreatorCodeService.lookup("LUCAS"))   // partial
        XCTAssertNil(CreatorCodeService.lookup("LUCAS500")) // close
    }

    func test_lookup_emptyOrWhitespace_returnsNil() {
        XCTAssertNil(CreatorCodeService.lookup(""))
        XCTAssertNil(CreatorCodeService.lookup("   "))
        XCTAssertNil(CreatorCodeService.lookup("\n"))
    }

    /// Guards against accidentally introducing duplicate codes that would
    /// silently make `lookup` non-deterministic between launches.
    func test_seededCodes_areUnique() {
        let codes = CreatorCodeService.seeded.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "Duplicate code in seeded list")
    }
}
