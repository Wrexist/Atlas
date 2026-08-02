import SwiftUI
import XCTest
@testable import Peptide

/// Covers the design-system primitives that carry real logic — the ones a
/// visual regression wouldn't catch until someone opened the app in the wrong
/// appearance.
final class DesignSystemTokenTests: XCTestCase {

    // MARK: - Spacing.concentric

    func test_concentric_subtractsTheInsetFromTheOuterRadius() {
        XCTAssertEqual(Spacing.concentric(in: 20, inset: 8), 12)
        XCTAssertEqual(Spacing.concentric(in: 28, inset: 12), 16)
    }

    /// A deep inset must degrade to "almost square", never to a negative
    /// radius — `RoundedRectangle` renders those unpredictably.
    func test_concentric_clampsRatherThanGoingNegative() {
        XCTAssertEqual(Spacing.concentric(in: 8, inset: 20), 2)
        XCTAssertEqual(Spacing.concentric(in: 0, inset: 0), 2)
    }

    func test_minimumHitTarget_matchesApplesFloor() {
        XCTAssertEqual(Spacing.minimumHitTarget, 44)
    }

    // MARK: - DisplayMode

    /// `.system` means "let iOS decide", which `preferredColorScheme` spells
    /// as `nil`. Returning `.dark` here would silently pin the app.
    func test_systemDisplayMode_defersToTheOS() {
        XCTAssertNil(DisplayMode.system.preferredScheme)
        XCTAssertEqual(DisplayMode.light.preferredScheme, .light)
        XCTAssertEqual(DisplayMode.dark.preferredScheme, .dark)
    }

    func test_displayMode_roundTripsThroughItsRawValue() {
        for mode in DisplayMode.allCases {
            XCTAssertEqual(DisplayMode(rawValue: mode.rawValue), mode)
        }
    }

    /// Installs that stored a mode before `.system` existed must still decode;
    /// an unknown value is the only case that should fall back.
    func test_displayMode_legacyStoredValuesStillDecode() {
        XCTAssertEqual(DisplayMode(rawValue: "dark"), .dark)
        XCTAssertEqual(DisplayMode(rawValue: "light"), .light)
        XCTAssertNil(DisplayMode(rawValue: "sepia"))
    }

    func test_displayMode_exposesAllThreeChoices() {
        XCTAssertEqual(DisplayMode.allCases.count, 3)
        XCTAssertEqual(Set(DisplayMode.allCases.map(\.displayName)).count, 3)
        XCTAssertFalse(DisplayMode.allCases.contains { $0.iconName.isEmpty })
    }

    // MARK: - Adaptive colours

    /// The whole point of `Color(light:dark:)` is that one token resolves
    /// differently per trait collection. If it ever collapses to a single
    /// value, light mode silently regresses to the dark palette.
    func test_adaptiveColor_resolvesDifferentlyPerInterfaceStyle() {
        let token = UIColor(Color(light: 0xFFFFFF, dark: 0x000000))
        let light = token.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = token.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }

    func test_surfaceTokensInvertBetweenSchemes() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        for token in [AppColor.background, AppColor.surfaceElevated, AppColor.surfaceSecondary] {
            let resolved = UIColor(token)
            XCTAssertGreaterThan(
                brightness(of: resolved.resolvedColor(with: light)),
                brightness(of: resolved.resolvedColor(with: dark)),
                "A surface token must be lighter in light mode than in dark mode"
            )
        }
    }

    func test_primaryInkInvertsWithTheSurface() {
        let resolved = UIColor(AppColor.textPrimary)
        XCTAssertLessThan(
            brightness(of: resolved.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))),
            brightness(of: resolved.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        )
    }

    /// The dark background was lifted off pure black so Liquid Glass has
    /// something to refract; a true-black backdrop renders the material flat.
    func test_darkBackgroundIsNotPureBlack() {
        let dark = UIColor(AppColor.background)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertGreaterThan(brightness(of: dark), 0.02)
    }

    private func brightness(of color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
