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

    // MARK: - Progress clamping

    /// A 0/0 score must draw an empty ring, not a full one — `min(1, .nan)`
    /// is 1, which is the trap `unitClamped` exists to avoid.
    func test_unitClamped_nonFiniteProgress_isZero() {
        XCTAssertEqual(Double.nan.unitClamped, 0)
        XCTAssertEqual(Double.infinity.unitClamped, 0)
        XCTAssertEqual((-Double.infinity).unitClamped, 0)
    }

    func test_unitClamped_outOfRangeProgress_clampsToUnitInterval() {
        XCTAssertEqual((-0.2).unitClamped, 0)
        XCTAssertEqual(0.4.unitClamped, 0.4)
        XCTAssertEqual(1.7.unitClamped, 1)
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

    /// Increase Contrast must firm up the quiet inks; nothing else in the
    /// app reads the setting.
    func test_secondaryInks_increaseContrast_moveAwayFromTheSurface() {
        for (style, darkens) in [(UIUserInterfaceStyle.light, true), (.dark, false)] {
            let normal = UITraitCollection(userInterfaceStyle: style)
            let high = normal.modifyingTraits { $0.accessibilityContrast = .high }
            for token in [AppColor.textSecondary, AppColor.textTertiary] {
                let resolved = UIColor(token)
                let normalBrightness = brightness(of: resolved.resolvedColor(with: normal))
                let highBrightness = brightness(of: resolved.resolvedColor(with: high))
                if darkens {
                    XCTAssertLessThan(highBrightness, normalBrightness)
                } else {
                    XCTAssertGreaterThan(highBrightness, normalBrightness)
                }
            }
        }
    }

    // MARK: - Stored-hex palettes

    /// A habit's stored hex is its dark-scheme hue; light mode must print a
    /// deeper stop, or the 11pt weekly count fades to under 2:1 on white.
    func test_habitTint_catalogSwatch_isDeeperInLightMode() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        for hex in HabitTintCatalog.all {
            let resolved = UIColor(HabitTintCatalog.color(for: hex))
            XCTAssertLessThan(
                brightness(of: resolved.resolvedColor(with: light)),
                brightness(of: resolved.resolvedColor(with: dark)),
                String(format: "Habit tint 0x%06X needs a deeper light stop", hex)
            )
        }
    }

    /// Older data may carry a hex outside today's catalog; it must still
    /// render as that colour rather than disappear.
    func test_habitTint_unknownHex_rendersAsStored() {
        let resolved = UIColor(HabitTintCatalog.color(for: 0x33AAFF))
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0x33 / 255, accuracy: 0.01)
        XCTAssertEqual(g, 0xAA / 255, accuracy: 0.01)
        XCTAssertEqual(b, 0xFF / 255, accuracy: 0.01)
    }

    func test_tierTint_isDeeperInLightMode() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        for tier in MomentumEngine.Tier.allCases {
            let resolved = UIColor(tier.tint)
            XCTAssertLessThan(
                brightness(of: resolved.resolvedColor(with: light)),
                brightness(of: resolved.resolvedColor(with: dark)),
                "\(tier) needs a deeper light stop"
            )
        }
    }

    // MARK: - AppFont.scaledValue

    /// Icon tiles size themselves with this, so it must match the glyph's
    /// font exactly: unchanged at the default size, larger at AX sizes.
    func test_scaledValue_defaultSize_isUnchanged() {
        XCTAssertEqual(AppFont.scaledValue(40, in: .large), 40, accuracy: 0.5)
    }

    func test_scaledValue_accessibilitySize_growsMonotonically() {
        let ax1 = AppFont.scaledValue(40, in: .accessibility1)
        let ax5 = AppFont.scaledValue(40, in: .accessibility5)
        XCTAssertGreaterThan(ax1, 40)
        XCTAssertGreaterThan(ax5, ax1)
    }

    // MARK: - SyncToast

    /// An Undo toast is a time-limited control: under VoiceOver or Switch
    /// Control it has to stay long enough to reach the button.
    @MainActor
    func test_syncToastDelay_actionWithAssistiveTech_isExtended() {
        let delay = SyncToast.dismissDelay(base: .seconds(5), hasAction: true, assistiveTechRunning: true)
        XCTAssertEqual(delay, .seconds(30))
    }

    @MainActor
    func test_syncToastDelay_withoutActionOrAssistiveTech_keepsBase() {
        XCTAssertEqual(
            SyncToast.dismissDelay(base: .seconds(5), hasAction: true, assistiveTechRunning: false),
            .seconds(5)
        )
        XCTAssertEqual(
            SyncToast.dismissDelay(base: .seconds(5), hasAction: false, assistiveTechRunning: true),
            .seconds(5)
        )
    }

    // MARK: - BenefitStyleMap

    func test_dnaRepairBenefit_getsTheImmuneStyleNotGenericRepair() {
        let style = BenefitStyleMap.style(for: "DNA Repair", fallbackColor: .clear)
        XCTAssertEqual(style.icon, "staroflife.fill")
    }

    /// First match wins, so a keyword containing an earlier one is dead.
    func test_benefitKeywords_neverShadowedByAnEarlierKeyword() {
        let keywords = BenefitStyleMap.mappings.map { $0.keyword }
        for (index, keyword) in keywords.enumerated() {
            for earlier in keywords[..<index] {
                XCTAssertFalse(
                    keyword.localizedCaseInsensitiveContains(earlier),
                    "\"\(keyword)\" is shadowed by \"\(earlier)\""
                )
            }
        }
    }

    private func brightness(of color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
