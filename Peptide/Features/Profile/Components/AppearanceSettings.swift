import SwiftUI

/// Width of the leading icon column shared by every settings row, so copy on
/// a second line can align under the title rather than under the icon.
private let iconColumnWidth: CGFloat = 24

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
                        subtitle: "Hides the app behind a quick \(biometricService.biometryName) check on launch. Your data isn't separately encrypted — this is a privacy screen, not full disk encryption.",
                        isOn: $store.profile.biometricLockEnabled
                    )
                    .onChange(of: dataStore.profile.biometricLockEnabled) { _, _ in
                        dataStore.persistProfile()
                    }
                }

                Divider().foregroundStyle(AppColor.glassBorder)

                ThemePickerRow(
                    selection: $themeBinding.theme
                )

                Divider().foregroundStyle(AppColor.glassBorder)

                DisplayModeRow(selection: $themeBinding.displayMode)

                Divider().foregroundStyle(AppColor.glassBorder)

                LanguagePickerRow()

                Divider().foregroundStyle(AppColor.glassBorder)

                MeasurementUnitRow(selection: $store.profile.bodyMetrics.unit)
                    .onChange(of: dataStore.profile.bodyMetrics.unit) { _, _ in
                        dataStore.persistProfile()
                    }
            }
        }
    }

    private var notificationStatusRow: some View {
        let limit = NotificationService.pendingRequestLimit
        let overLimit = notificationService.requestedCount > limit
        return HStack(spacing: Spacing.sm) {
            Image(systemName: overLimit ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(AppFont.scaled(11))
                .foregroundStyle(overLimit ? .orange : AppColor.accentPrimary)

            if overLimit {
                Text("\(notificationService.scheduledCount) of \(notificationService.requestedCount) reminders active (iOS limit: \(limit))")
                    .font(AppFont.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("\(notificationService.scheduledCount) reminders scheduled")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(.leading, iconColumnWidth + Spacing.md)
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
            // Habit reminders survive a dose-reminder toggle-off — they're
            // opted into separately on each habit.
            NotificationService.shared.cancelProtocolReminders()
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: iconColumnWidth)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColor.accentPrimary)
                .accessibilityLabel(title)
        }
    }
}

private struct ThemePickerRow: View {
    @Binding var selection: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "paintpalette.fill")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: iconColumnWidth)

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
            .padding(.leading, iconColumnWidth + Spacing.md)
        }
    }

    private func swatch(for theme: AppThemeColor) -> some View {
        let isSelected = selection == theme
        return Button {
            guard selection != theme else { return }
            withAnimation(.snappy(duration: 0.2)) {
                selection = theme
            }
            Haptics.impact(.light)
        } label: {
            Circle()
                .fill(theme.primary)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(AppColor.textPrimary.opacity(isSelected ? 0.95 : 0.0), lineWidth: 2)
                        .padding(-3)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(AppFont.scaled(12, weight: .bold))
                        .foregroundStyle(AppColor.onAccent)
                        .opacity(isSelected ? 1 : 0)
                )
                .minimumHitArea()
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }
}

/// Auto / Light / Dark. Replaces the static "Appearance — Dark" info row that
/// stood in while `AppColor` was dark-only; every surface token now resolves
/// per trait collection, so all three modes are live.
private struct DisplayModeRow: View {
    @Binding var selection: DisplayMode

    var body: some View {
        SettingsPickerRow(
            icon: selection.iconName,
            title: "Appearance",
            subtitle: LocalizedStringKey(selection.displayName)
        ) {
            Picker("Appearance", selection: $selection) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Metric / Imperial for the body-metric surfaces (weight, height, waist,
/// temperature). Peptide doses stay in mcg/mg regardless — they're prescribed
/// in metric everywhere.
private struct MeasurementUnitRow: View {
    @Binding var selection: MeasurementUnit

    var body: some View {
        SettingsPickerRow(
            icon: "ruler.fill",
            title: "Units",
            subtitle: selection == .metric ? "kg · cm · °C" : "lb · in · °F"
        ) {
            Picker("Units", selection: $selection) {
                Text("Metric").tag(MeasurementUnit.metric)
                Text("Imperial").tag(MeasurementUnit.imperial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Shared skeleton for a settings row whose control is wide enough to need
/// its own line beneath the label (matches `ThemePickerRow`'s layout).
private struct SettingsPickerRow<Control: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: iconColumnWidth)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()
            }

            control()
                .padding(.leading, iconColumnWidth + Spacing.md)
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
    .environment(LocalizationManager.shared)
    .preferredColorScheme(.dark)
}
