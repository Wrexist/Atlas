import SwiftUI
import UIKit

/// The single source of truth for colour in the app.
///
/// **Rule:** feature views must use `AppColor` tokens — never a raw
/// `Color(red:…)` / `Color(hex:…)` / `Color.white` literal — so the whole app
/// stays on one theme, adapts to light *and* dark, and a palette change is one
/// edit. See `docs/PREMIUM_CONSISTENCY_PLAN.md`.
///
/// Every token that describes a *surface* or *ink* resolves per
/// `UITraitCollection`, so Display mode → System renders a correct light
/// appearance without a second palette.
///
/// **Whitelisted domain colours** (intentionally literal, do NOT tokenize):
/// the macro-ring colours (`macro*`), HealthKit metric colours (`metric*`),
/// `streak` / `achievement`, the anatomy primary/secondary tints in
/// `MuscleMapView`, the notes mood-rating scale in `ProtocolNotesTimeline`,
/// the multi-colour onboarding showcase in `WhatsNewPage`, and the
/// deliberately-distinct Screenshot-mode dev row. These encode a real-world
/// concept, not the brand — but they still carry a light variant where the
/// dark-mode value would fail contrast on a light surface.
enum AppColor {
    // MARK: - Surfaces
    //
    // The dark values are lifted off pure black (was `0x0A0A0A`) so Liquid
    // Glass has something to refract; a true-black backdrop makes the iOS 26
    // material read as flat grey. The light values are a warm neutral rather
    // than pure white for the same reason.

    static let background = Color(light: 0xF4F4F7, dark: 0x101013)
    static let surfaceElevated = Color(light: 0xFCFCFD, dark: 0x1C1C21)
    static let surfaceSecondary = Color(light: 0xFAFAFC, dark: 0x17171B)

    // MARK: - Brand accents

    static var accentPrimary: Color { ThemeManager.shared.theme.primary }
    static var accentLight: Color { ThemeManager.shared.theme.light }
    static var accentDark: Color { ThemeManager.shared.theme.dark }
    static var accentGlow: Color { ThemeManager.shared.theme.primary.opacity(0.3) }
    static var glassTint: Color { ThemeManager.shared.theme.primary.opacity(0.15) }

    // MARK: - Ink

    static let textPrimary = Color(light: 0x111114, dark: 0xF7F7FA)
    static let textSecondary = Color(light: 0x5B5B63, dark: 0xA0A0A0)
    /// Deepened from `#666666` to clear WCAG AA (4.5:1) against the dark
    /// background and elevated surfaces. The previous value sat at ~3:1.
    static let textTertiary = Color(light: 0x6E6E76, dark: 0x888888)
    static var textHighlight: Color { ThemeManager.shared.theme.highlight }

    /// Ink for content painted **on top of** an accent-filled or photographic
    /// surface (filled buttons, vial glyphs, gradient hero cards). Constant
    /// across schemes on purpose — the surface underneath is always dark.
    ///
    /// Very slightly off pure white, like every other neutral here: `#FFF`
    /// against a saturated fill is harsher than it needs to be, and the
    /// difference is the kind you feel rather than see.
    static let onAccent = Color(hex: 0xFCFCFD)

    /// The accent stop to *fill* with when `onAccent` is printed on top.
    ///
    /// `accentPrimary` can't do this job in both schemes: it's read as ink
    /// on the background 280 times, so the dark-scheme value is a bright
    /// brand colour — and near-white on emerald-500 is 2.5:1. The ramp's
    /// dark stop carries `onAccent` at 5.3:1 or better in every theme and
    /// both schemes, which is why filled accent surfaces use this instead.
    static var accentFill: Color { ThemeManager.shared.theme.dark }

    // MARK: - Status

    static let destructive = Color(light: 0xD32F2F, dark: 0xFF4444)
    static let warning = Color(light: 0x9A6B00, dark: 0xFFB800)
    static var success: Color { ThemeManager.shared.theme.primary }

    // MARK: - Glass

    /// Hairline separating a glass surface from the backdrop. Light mode
    /// borrows a dark hairline; dark mode a light one.
    static let glassBorder = Color.adaptive(
        light: Color.black.opacity(0.10),
        dark: Color.white.opacity(0.08)
    )
    static var glassBorderActive: Color { ThemeManager.shared.theme.primary.opacity(0.3) }
    /// The faint wash that lifts a card off the backdrop on pre-iOS-26 OSes.
    static let cardOverlay = Color.adaptive(
        light: Color.black.opacity(0.03),
        dark: Color.white.opacity(0.04)
    )

    // MARK: - Directional feedback
    //
    // "This moved the right way" / "this moved the wrong way". Distinct from
    // `success` (which follows the brand accent) and `destructive` (which
    // means a irreversible action), these read as *data* commentary and were
    // previously ~20 near-identical inline `Color(red:green:blue:)` literals
    // scattered across Labs, Biology, Meals, Train and the weekly recap.

    /// Improving trend, in-range lab value, on-track streak.
    static let positive = Color(light: 0x2F8F5B, dark: 0x66C78C)
    /// Regressing trend or an above-range lab value. Softer than
    /// `destructive` — it's an observation, not an error.
    static let negative = Color(light: 0xB4573C, dark: 0xEE8C70)
    /// Below-range lab value — cool counterpart to `negative`.
    static let belowRange = Color(light: 0x2F6E96, dark: 0x8CC7EB)

    // MARK: - Feature accents

    /// Indigo that identifies the weekly-recap surfaces (hero card, detail
    /// view, past-weeks list) and the screenshot/demo chrome.
    static let recap = Color(light: 0x5A5FCF, dark: 0x7A80EB)

    /// The two stops of the paywall / quick-log call-to-action gradient. A
    /// deliberate violet that stays constant across brand themes so the
    /// single most important button in the app is always the same button.
    static let ctaGradientStart = Color(light: 0x4238C4, dark: 0x4F46E5)
    static let ctaGradientEnd = Color(light: 0x6620C0, dark: 0x7C3AED)

    /// Hero-ring identities. Adherence follows the brand accent; Recovery and
    /// Sleep get their own hues so the three rings stay tellable apart at a
    /// glance even in a screenshot. Stops run light → deep so the arc reads
    /// as having direction.
    static let ringRecoveryStart = Color(light: 0x5E8A1F, dark: 0xB8F557)
    static let ringRecoveryEnd = Color(light: 0x2F7A3B, dark: 0x47C75C)
    static let ringSleepStart = Color(light: 0x6B63C4, dark: 0xA89EF5)
    static let ringSleepEnd = Color(light: 0x453FA8, dark: 0x7366D9)

    // MARK: - Semantic accents
    //
    // Theme-independent colors for icons whose meaning is tied to a real-world
    // concept (a flame is always warm orange, gold is always achievement). Pulled
    // out of inline hex literals so every site that renders the same idea uses
    // the same color and a future palette tweak is one edit.

    /// Warm orange used for streak flames and "consecutive days" affordances.
    static let streak = Color(light: 0xC26A2B, dark: 0xE88D4F)

    /// Soft gold used for achievement / trophy iconography.
    static let achievement = Color(light: 0x9C7714, dark: 0xD4A844)

    /// Warm amber for the workout "perceived effort" indicator.
    static let perceivedEffort = Color(light: 0xB2740F, dark: 0xFFB347)

    /// Canonical macro colors. Match the rings + legend on the Nutrition card
    /// so the same idea reads consistently across the app.
    static let macroProtein = Color(light: 0xB56F0B, dark: 0xEF9F27)
    static let macroProteinLight = Color(light: 0xB8791E, dark: 0xF5C56C)
    static let macroWater = Color(light: 0x1F6FC0, dark: 0x378ADD)
    static let macroWaterLight = Color(light: 0x3F8BD6, dark: 0x7CC5FF)
    /// Carbs and fat. Protein already had a token; these two did not, so any
    /// surface breaking a meal into P/C/F had no colours to do it with.
    /// Chosen to stay clear of `macroProtein`'s amber and `macroWater`'s
    /// blue, and darkened in light mode like every other ink here so they
    /// clear 4.5:1 on all three surfaces.
    static let macroCarbs = Color(light: 0x2A6F55, dark: 0x5FD3A0)
    static let macroFat = Color(light: 0x9E4055, dark: 0xE8899F)

    /// HealthKit metric category colors. Each represents a physiological
    /// signal, not the brand — they intentionally stay constant across themes,
    /// but darken in light mode so they clear contrast on a white card.
    static let metricHeartRate = Color(light: 0xA84343, dark: 0xCF7272)
    static let metricHRV = Color(light: 0x6B44A3, dark: 0x9B72CF)
    static let metricSleep = Color(light: 0x9C7714, dark: 0xD4A844)
    static let metricActivity = Color(light: 0x35603F, dark: 0x4A7C59)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// A token that resolves to a different hex per interface style, so one
    /// `AppColor` entry serves both light and dark without a parallel palette.
    init(light: UInt, dark: UInt, opacity: Double = 1.0) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .light ? light : dark, alpha: opacity)
        })
    }

    /// Trait-resolving pair for tokens whose two halves aren't plain hexes
    /// (translucent overlays, hairlines).
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .light ? light : dark)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
