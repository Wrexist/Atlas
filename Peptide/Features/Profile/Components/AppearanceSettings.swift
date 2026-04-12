import SwiftUI

struct AppearanceSettings: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        @Bindable var store = dataStore

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                SettingsToggleRow(
                    icon: "bell.fill",
                    title: "Dose Reminders",
                    subtitle: "Get notified for scheduled doses",
                    isOn: $store.profile.doseRemindersEnabled
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    title: "Haptic Feedback",
                    subtitle: "Vibrate on interactions",
                    isOn: $store.profile.hapticFeedbackEnabled
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsInfoRow(
                    icon: "moon.fill",
                    title: "Appearance",
                    value: "Dark"
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsInfoRow(
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

private struct SettingsInfoRow: View {
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
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AppearanceSettings()
            .padding(Spacing.screenPadding)
    }
    .environment(DataStore())
    .preferredColorScheme(.dark)
}
