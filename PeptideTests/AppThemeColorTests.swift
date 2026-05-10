import XCTest
@testable import Peptide

final class AppThemeColorTests: XCTestCase {

    // MARK: - Direct decode

    func test_resolving_currentRawValue_returnsExactCase() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "purpleGradient"), .purpleGradient)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "ocean"), .ocean)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "teal"), .teal)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "amber"), .amber)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "onyx"), .onyx)
    }

    // MARK: - Migration from the previous 6-theme palette

    /// Greens (forest, cyan) collapse onto teal — the closest current case.
    func test_resolving_greenLegacyCases_mapToTeal() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "forest"), .teal)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "cyan"),   .teal)
    }

    /// Purples / pinks (amethyst, rose) collapse onto purpleGradient.
    func test_resolving_purpleLegacyCases_mapToPurpleGradient() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "amethyst"), .purpleGradient)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "rose"),     .purpleGradient)
    }

    func test_resolving_sunsetLegacyCase_mapsToAmber() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "sunset"), .amber)
    }

    // MARK: - Defaults

    func test_resolving_emptyOrUnknown_fallsBackToBrandDefault() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: ""),       .purpleGradient)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "garbage"), .purpleGradient)
    }

    // MARK: - Display mode

    func test_displayMode_preferredScheme_matchesCase() {
        XCTAssertEqual(DisplayMode.light.preferredScheme, .light)
        XCTAssertEqual(DisplayMode.dark.preferredScheme,  .dark)
    }

    func test_appThemeColor_caseCount_matchesSpec() {
        XCTAssertEqual(AppThemeColor.allCases.count, 5)
    }
}
