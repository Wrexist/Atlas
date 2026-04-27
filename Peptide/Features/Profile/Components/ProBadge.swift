import SwiftUI

struct ProBadge: View {
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
            Text("PRO")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(AppColor.accentLight)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background {
            Capsule()
                .fill(AppColor.accentPrimary.opacity(0.2))
                .overlay {
                    Capsule()
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }
        }
    }
}

struct UpgradePromptCard: View {
    @State private var showPaywall = false

    var body: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColor.accentLight)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Upgrade to Pro")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Unlimited protocols, full analytics, and more")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }

                GlassButton(title: "See Plans", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    showPaywall = true
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
