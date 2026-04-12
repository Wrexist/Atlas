import SwiftUI

enum AppColor {
    static let background = Color(hex: 0x0A0A0A)
    static let surfaceElevated = Color(hex: 0x1A1A1A)
    static let surfaceSecondary = Color(hex: 0x141414)

    static let accentPrimary = Color(hex: 0x4A7C59)
    static let accentLight = Color(hex: 0x6BAF7E)
    static let accentDark = Color(hex: 0x3A6247)
    static let accentGlow = Color(hex: 0x4A7C59).opacity(0.3)
    static let glassTint = Color(hex: 0x4A7C59).opacity(0.15)

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xA0A0A0)
    static let textTertiary = Color(hex: 0x666666)
    static let textHighlight = Color(hex: 0xC8D8C0)

    static let destructive = Color(hex: 0xFF4444)
    static let warning = Color(hex: 0xFFB800)
    static let success = Color(hex: 0x4A7C59)

    static let glassBorder = Color.white.opacity(0.08)
    static let glassBorderActive = Color(hex: 0x4A7C59).opacity(0.3)
    static let cardOverlay = Color.white.opacity(0.04)
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
