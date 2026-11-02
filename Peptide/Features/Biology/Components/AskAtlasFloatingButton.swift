import SwiftUI

/// "Ask Atlas" floating over the Biology tab: a glass capsule that folds to
/// its sparkle while the list scrolls and opens back out when it settles.
/// One shape morphs between the two, so the change reads as the same
/// button getting out of the way rather than a swap.
struct AskAtlasFloatingButton: View {
    let isCollapsed: Bool
    /// Free users see the Pro flag; the tap still opens the paywall.
    let showsProBadge: Bool
    let action: () -> Void

    private static let height = Spacing.minimumHitTarget + Spacing.sm

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                if !isCollapsed {
                    Text("Ask Atlas")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                    if showsProBadge {
                        Badge("Pro")
                            .transition(.opacity)
                    }
                }
            }
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, isCollapsed ? 0 : Spacing.lg)
            .frame(minWidth: Self.height, minHeight: Self.height)
            .glassControl(
                .capsule,
                tint: AppColor.accentPrimary.opacity(0.18),
                border: AppColor.glassBorderActive,
                interactive: false
            )
            .appShadow(AppShadow.glassElevated)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .appAnimation(AppAnimation.springSnappy, value: isCollapsed)
        .accessibilityLabel(Text("Ask Atlas"))
        .accessibilityHint(Text("Opens an AI chat about today's biology"))
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        AskAtlasFloatingButton(isCollapsed: false, showsProBadge: false) {}
        AskAtlasFloatingButton(isCollapsed: false, showsProBadge: true) {}
        AskAtlasFloatingButton(isCollapsed: true, showsProBadge: false) {}
    }
    .padding(Spacing.screenPadding)
    .background(AppColor.background)
}
