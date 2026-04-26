import SwiftUI

struct AppearanceSettings: View {
    @Environment(DataStore.self) private var dataStore
    @State private var notificationService = NotificationService.shared
    @State private var biometricService = BiometricService.shared
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        @Bindable var store = dataStore
        @Bindable var themeBinding = themeManager

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

                if biometricService.isAvailable {
                    Divider().foregroundStyle(AppColor.glassBorder)

                    SettingsToggleRow(
                        icon: biometricService.biometryIcon,
                        title: "\(biometricService.biometryName) Lock",
                        subtitle: "Require authentication on launch",
                        isOn: $store.profile.biometricLockEnabled
                    )
                    .onChange(of: dataStore.profile.biometricLockEnabled) { _, _ in
                        dataStore.persistProfile()
                    }
                }

                Divider().foregroundStyle(AppColor.glassBorder)

                ThemePickerRow(
                    selection: $themeBinding.theme,
                    hapticEnabled: dataStore.profile.hapticFeedbackEnabled
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
                    // Flip back to false; this triggers onChange again with enabled=false,
                    // which calls cancelAll() -- redundant but harmless since nothing is scheduled.
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

private struct ThemePickerRow: View {
    @Binding var selection: AppThemeColor
    let hapticEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Accent Color")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(selection.displayName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()
            }

            HStack(spacing: Spacing.md) {
                ForEach(AppThemeColor.allCases) { theme in
                    swatch(for: theme)
                }
            }
            .padding(.leading, 36)
        }
    }

    private func swatch(for theme: AppThemeColor) -> some View {
        let isSelected = selection == theme
        return Button {
            guard selection != theme else { return }
            withAnimation(.snappy(duration: 0.2)) {
                selection = theme
            }
            if hapticEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            Circle()
                .fill(theme.primary)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.0), lineWidth: 2)
                        .padding(-3)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .opacity(isSelected ? 1 : 0)
                )
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .buttonStyle(.plain)
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
