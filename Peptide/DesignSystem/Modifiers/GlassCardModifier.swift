import SwiftUI

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cardCornerRadius
    var tinted: Bool = false
    var padding: CGFloat = Spacing.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tinted ? AppColor.glassTint : AppColor.cardOverlay)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                tinted ? AppColor.glassBorderActive : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(in: .rect(cornerRadius: cornerRadius))
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
