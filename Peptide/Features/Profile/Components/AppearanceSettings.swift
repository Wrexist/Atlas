import SwiftUI

struct AppearanceSettings: View {
    @State private var hapticEnabled = true
    @State private var notificationsEnabled = true

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                SettingsToggleRow(
                    icon: "bell.fill",
                    title: "Dose Reminders",
                    subtitle: "Get notified for scheduled doses",
                    isOn: $notificationsEnabled
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    title: "Haptic Feedback",
                    subtitle: "Vibrate on interactions",
                    isOn: $hapticEnabled
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsRow(
                    icon: "moon.fill",
                    title: "Appearance",
                    value: "Dark"
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsRow(
                    icon: "globe",
                    title: "Units",
                    value: "Metric (mcg)"
                )
            }
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColor.accentPrimary)
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 24)

            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            Text(value)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AppearanceSettings()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
