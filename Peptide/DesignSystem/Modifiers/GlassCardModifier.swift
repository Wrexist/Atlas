import SwiftUI

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cardCornerRadius
    var tinted: Bool = false
    var padding: CGFloat = Spacing.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassSurface(cornerRadius: cornerRadius, tinted: tinted)
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = Spacing.cardCornerRadius,
        tinted: Bool = false,
        padding: CGFloat = Spacing.cardPadding
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tinted: tinted, padding: padding))
    }
}
