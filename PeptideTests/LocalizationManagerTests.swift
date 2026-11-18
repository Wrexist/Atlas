import SwiftUI
import XCTest
@testable import Peptide

final class LocalizationManagerTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private static let key = "preferredLanguageCode"

    override func setUp() {
        super.setUp()
        defaults.removeObject(forKey: Self.key)
        // Reset the live singleton so tests start clean. Direct mutation through
        // the public binding is the supported re-init path.
        LocalizationManager.shared.selectedCode = nil
    }

    override func tearDown() {
        LocalizationManager.shared.selectedCode = nil
        defaults.removeObject(forKey: Self.key)
        super.tearDown()
    }

    // MARK: - selectedCode round-trip

    func test_settingSelectedCode_persistsToDefaults() {
        LocalizationManager.shared.selectedCode = "sv"
        XCTAssertEqual(defaults.string(forKey: Self.key), "sv")
    }

    func test_clearingSelectedCode_removesDefaultsEntry() {
        LocalizationManager.shared.selectedCode = "sv"
        XCTAssertNotNil(defaults.string(forKey: Self.key))
        LocalizationManager.shared.selectedCode = nil
        XCTAssertNil(defaults.string(forKey: Self.key))
    }

    // MARK: - selectedLanguage mapping

    func test_selectedLanguage_returnsKnownLanguageForKnownCode() {
        LocalizationManager.shared.selectedCode = "sv"
        XCTAssertEqual(LocalizationManager.shared.selectedLanguage, .swedish)
    }

    func test_selectedLanguage_returnsNilForUnknownCode() {
        LocalizationManager.shared.selectedCode = "xx-Unknown"
        XCTAssertNil(LocalizationManager.shared.selectedLanguage)
    }

    func test_selectedLanguage_returnsNilWhenUnset() {
        XCTAssertNil(LocalizationManager.shared.selectedLanguage)
    }

    // MARK: - effectiveLocale

    func test_effectiveLocale_followsSelectedCode() {
        LocalizationManager.shared.selectedCode = "sv"
        XCTAssertEqual(LocalizationManager.shared.effectiveLocale.identifier, "sv")
    }

    func test_effectiveLocale_fallsBackToAutoupdatingWhenUnset() {
        // No selected code → autoupdatingCurrent. Verify we don't return a
        // hard-coded specific identifier.
        let locale = LocalizationManager.shared.effectiveLocale
        XCTAssertEqual(locale, .autoupdatingCurrent)
    }

    // MARK: - AppLanguage round-trip

    func test_AppLanguage_fromCode_acceptsAllSupportedCodes() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage.from(code: language.rawValue), language)
        }
    }

    func test_AppLanguage_fromCode_nilForUnknown() {
        XCTAssertNil(AppLanguage.from(code: nil))
        XCTAssertNil(AppLanguage.from(code: ""))
        XCTAssertNil(AppLanguage.from(code: "xx-yy"))
    }

    func test_AppLanguage_swedish_isOffered() {
        XCTAssertEqual(AppLanguage.from(code: "sv"), .swedish)
        XCTAssertEqual(AppLanguage.swedish.nativeName, "Svenska")
    }
}
