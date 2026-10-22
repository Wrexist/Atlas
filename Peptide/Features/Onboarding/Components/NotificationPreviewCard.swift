import SwiftUI

/// Mock iOS lock-screen notification used on the consistency onboarding
/// step to show the user *what* a reminder actually looks like before they
/// grant permission. Pure presentation — does not interact with
/// `UNUserNotificationCenter`.
struct NotificationPreviewCard: View {
    var appName: LocalizedStringKey = "Atlas"
    var title: LocalizedStringKey = "Leg day in 30 minutes"
    var subtitle: LocalizedStringKey = "Hit your second session of the week"
    var timestamp: LocalizedStringKey = "now"

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appName)
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer(minLength: Spacing.sm)
                    Text(timestamp)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Text(title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)

                Text(subtitle)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.md)
        .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        Image("AtlasLogo")
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous))
            .accessibilityHidden(true)
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
