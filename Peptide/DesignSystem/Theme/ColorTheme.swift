import SwiftUI

enum AppColor {
    static let background = Color(hex: 0x0A0A0A)
    static let surfaceElevated = Color(hex: 0x1A1A1A)
    static let surfaceSecondary = Color(hex: 0x141414)

    static var accentPrimary: Color { ThemeManager.shared.theme.primary }
    static var accentLight: Color { ThemeManager.shared.theme.light }
    static var accentDark: Color { ThemeManager.shared.theme.dark }
    static var accentGlow: Color { ThemeManager.shared.theme.primary.opacity(0.3) }
    static var glassTint: Color { ThemeManager.shared.theme.primary.opacity(0.15) }

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xA0A0A0)
    // Deepened from #666666 to clear WCAG AA (4.5:1) against the dark
    // background and elevated surfaces. The previous value sat at ~3:1.
    static let textTertiary = Color(hex: 0x888888)
    static var textHighlight: Color { ThemeManager.shared.theme.highlight }

    static let destructive = Color(hex: 0xFF4444)
    static let warning = Color(hex: 0xFFB800)
    static var success: Color { ThemeManager.shared.theme.primary }

    static let glassBorder = Color.white.opacity(0.08)
    static var glassBorderActive: Color { ThemeManager.shared.theme.primary.opacity(0.3) }
    static let cardOverlay = Color.white.opacity(0.04)

    // MARK: - Semantic accents
    //
    // Theme-independent colors for icons whose meaning is tied to a real-world
    // concept (a flame is always warm orange, gold is always achievement). Pulled
    // out of inline hex literals so every site that renders the same idea uses
    // the same color and a future palette tweak is one edit.

    /// Warm orange used for streak flames and "consecutive days" affordances.
    static let streak = Color(hex: 0xE88D4F)

    /// Soft gold used for achievement / trophy iconography.
    static let achievement = Color(hex: 0xD4A844)

    /// Canonical macro colors. Match the rings + legend on the Lifestyle
    /// Nutrition card so the same idea reads consistently across the app.
    static let macroProtein = Color(hex: 0xEF9F27)
    static let macroProteinLight = Color(hex: 0xF5C56C)
    static let macroWater = Color(hex: 0x378ADD)
    static let macroWaterLight = Color(hex: 0x7CC5FF)

    /// HealthKit metric category colors. Each represents a physiological
    /// signal, not the brand — they intentionally stay constant across themes.
    static let metricHeartRate = Color(hex: 0xCF7272)
    static let metricHRV = Color(hex: 0x9B72CF)
    static let metricSleep = Color(hex: 0xD4A844)
    static let metricActivity = Color(hex: 0x4A7C59)
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
}
