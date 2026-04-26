import SwiftUI

enum AppShadow {
    static let glassSubtle = Shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    static let glassElevated = Shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    static let glassDeep = Shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
    static var accentGlow: Shadow { Shadow(color: AppColor.accentPrimary.opacity(0.3), radius: 12, x: 0, y: 4) }
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
