import XCTest
import SwiftUI
@testable import Peptide

final class AppThemeColorTests: XCTestCase {

    // MARK: - Direct decode

    func test_resolving_currentRawValue_returnsExactCase() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "purpleGradient"), .purpleGradient)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "ocean"), .ocean)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "teal"), .teal)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "amber"), .amber)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "onyx"), .onyx)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "ember"), .ember)
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

    /// The brand default is `.teal` (emerald), and has been since the palette
    /// was cut from six themes to five — this test still asserted the old
    /// `.purpleGradient` default and was failing against the shipped
    /// behaviour, not describing it.
    func test_resolving_emptyOrUnknown_fallsBackToBrandDefault() {
        XCTAssertEqual(AppThemeColor.resolving(rawValue: ""),        .teal)
        XCTAssertEqual(AppThemeColor.resolving(rawValue: "garbage"), .teal)
        XCTAssertEqual(AppThemeColor.allCases.first, .teal)
    }

    // MARK: - Display mode

    func test_displayMode_preferredScheme_matchesCase() {
        XCTAssertEqual(DisplayMode.light.preferredScheme, .light)
        XCTAssertEqual(DisplayMode.dark.preferredScheme,  .dark)
        XCTAssertNil(DisplayMode.system.preferredScheme)
    }

    // MARK: - Accent handed to widgets and the Watch

    /// `accent` is a literal copy of each ramp's `primary` stop; if the two
    /// drift, the widgets and the Watch paint a different colour than the app.
    func test_accent_matchesPrimaryInBothSchemes() {
        for theme in AppThemeColor.allCases {
            let primary = UIColor(theme.primary)
            XCTAssertEqual(hex(primary, .light), theme.accent.light, "\(theme) light")
            XCTAssertEqual(hex(primary, .dark), theme.accent.dark, "\(theme) dark")
        }
    }

    private func hex(_ color: UIColor, _ style: UIUserInterfaceStyle) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let byte = { (component: CGFloat) in UInt32((component * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    func test_appThemeColor_caseCount_matchesSpec() {
        XCTAssertEqual(AppThemeColor.allCases.count, 6)
    }
}
