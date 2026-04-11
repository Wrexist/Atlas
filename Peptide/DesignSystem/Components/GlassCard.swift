import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat
    var tinted: Bool
    var padding: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        cornerRadius: CGFloat = Spacing.cardCornerRadius,
        tinted: Bool = false,
        padding: CGFloat = Spacing.cardPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tinted = tinted
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
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
            .glassEffect(in: .rect(cornerRadius: cornerRadius))
    }
}

struct GlassCardCompact<Content: View>: View {
    var tinted: Bool
    @ViewBuilder var content: () -> Content

    init(tinted: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.tinted = tinted
        self.content = content
    }

    var body: some View {
        GlassCard(cornerRadius: Spacing.smallCornerRadius, tinted: tinted, padding: Spacing.md) {
            content()
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()

        VStack(spacing: Spacing.lg) {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Glass Card")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("A translucent container with depth")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(tinted: true) {
                Text("Tinted Glass Card")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.accentLight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
