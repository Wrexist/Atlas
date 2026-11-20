import SwiftUI

/// The app's card: content on the raised surface at the standard padding.
/// A card that opens something is a `Button` whose label is the card, with
/// `.buttonStyle(.cardPress)` so it dips under the finger like every other
/// tappable surface; a card that appears in place of an empty state or a
/// placeholder uses `.transition(.contentAppear)`.
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
            .glassSurface(cornerRadius: cornerRadius, tinted: tinted)
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
