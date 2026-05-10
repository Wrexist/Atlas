import SwiftUI

/// Mock iOS lock-screen notification used on the consistency onboarding
/// step to show the user *what* a reminder actually looks like before they
/// grant permission. Pure presentation — does not interact with
/// `UNUserNotificationCenter`.
struct NotificationPreviewCard: View {
    var appName: LocalizedStringKey = "PeptideX"
    var title: LocalizedStringKey = "Time for your BPC-157 dose"
    var subtitle: LocalizedStringKey = "Day 14 of 84 — stay consistent"
    var timestamp: LocalizedStringKey = "now"

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer(minLength: Spacing.sm)
                    Text(timestamp)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Text(title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)

                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.rect(cornerRadius: Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        Image(systemName: "flask.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentLight, AppColor.accentPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        NotificationPreviewCard()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
