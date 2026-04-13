import SwiftUI

struct AppearanceSettings: View {
    @Environment(DataStore.self) private var dataStore
    @State private var notificationService = NotificationService.shared

    var body: some View {
        @Bindable var store = dataStore

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SettingsToggleRow(
                        icon: "bell.fill",
                        title: "Dose Reminders",
                        subtitle: "Get notified for scheduled doses",
                        isOn: $store.profile.doseRemindersEnabled
                    )
                    .onChange(of: dataStore.profile.doseRemindersEnabled) { _, enabled in
                        handleDoseRemindersToggle(enabled)
                    }

                    if dataStore.profile.doseRemindersEnabled, notificationService.requestedCount > 0 {
                        notificationStatusRow
                    }
                }

                Divider().foregroundStyle(AppColor.glassBorder)

                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    title: "Haptic Feedback",
                    subtitle: "Vibrate on interactions",
                    isOn: $store.profile.hapticFeedbackEnabled
                )
                .onChange(of: dataStore.profile.hapticFeedbackEnabled) { _, _ in
                    dataStore.persistProfile()
                }

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

    private var notificationStatusRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: notificationService.requestedCount > 64 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(notificationService.requestedCount > 64 ? .orange : AppColor.accentPrimary)

            if notificationService.requestedCount > 64 {
                Text("\(notificationService.scheduledCount) of \(notificationService.requestedCount) reminders active (iOS limit: 64)")
                    .font(AppFont.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("\(notificationService.scheduledCount) reminders scheduled")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(.leading, 36)
    }

    private func handleDoseRemindersToggle(_ enabled: Bool) {
        dataStore.persistProfile()
        if enabled {
            Task {
                let authorized = await NotificationService.shared.requestAuthorization()
                if authorized {
                    NotificationService.shared.scheduleNotifications(for: dataStore.activeProtocols)
                } else {
                    dataStore.profile.doseRemindersEnabled = false
                    dataStore.persistProfile()
                }
            }
        } else {
            NotificationService.shared.cancelAll()
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
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
