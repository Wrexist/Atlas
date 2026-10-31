import SwiftUI

/// Elevation tokens. Light surfaces get a far lighter drop than dark ones —
/// a dark-mode-weight black shadow reads as a smudge on a pale card.
enum AppShadow {
    static let glassSubtle = Shadow(color: ink(light: 0.08, dark: 0.2), radius: 8, x: 0, y: 4)
    static let glassElevated = Shadow(color: ink(light: 0.12, dark: 0.3), radius: 16, x: 0, y: 8)
    static let glassDeep = Shadow(color: ink(light: 0.16, dark: 0.4), radius: 24, x: 0, y: 12)
    /// Floating toasts and banners that hover over scrolling content.
    static let toast = Shadow(color: ink(light: 0.1, dark: 0.2), radius: 12, x: 0, y: 4)
    /// The card's drop: a tight contact edge plus a wide, faint ambient
    /// lift. Dark mode needs more alpha for the same lift, since the drop
    /// lands on a near-black page.
    static let paperContact = Shadow(color: ink(light: 0.04, dark: 0.5), radius: 1.5, x: 0, y: 1)
    static let paperAmbient = Shadow(color: ink(light: 0.07, dark: 0.45), radius: 28, x: 0, y: 14)
    static var accentGlow: Shadow { Shadow(color: AppColor.accentPrimary.opacity(0.3), radius: 12, x: 0, y: 4) }

    private static func ink(light: Double, dark: Double) -> Color {
        .adaptive(light: .black.opacity(light), dark: .black.opacity(dark))
    }
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func appShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
