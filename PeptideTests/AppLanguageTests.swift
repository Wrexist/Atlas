import XCTest
@testable import Peptide

final class AppLanguageTests: XCTestCase {

    func test_rawValue_unknownCode_isNotALanguage() {
        XCTAssertNil(AppLanguage(rawValue: ""))
        XCTAssertNil(AppLanguage(rawValue: "xx-yy"))
    }

    func test_swedish_isNamedInSwedish() {
        XCTAssertEqual(AppLanguage(rawValue: "sv"), .swedish)
        XCTAssertEqual(AppLanguage.swedish.nativeName, "Svenska")
    }

    func test_shipped_onlyListsLanguagesTheBundleCarries() {
        let bundled = Set(Bundle.main.localizations)
        XCTAssertTrue(AppLanguage.shipped.allSatisfy { bundled.contains($0.rawValue) })
    }
}
