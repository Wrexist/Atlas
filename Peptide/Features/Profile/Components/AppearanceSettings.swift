import SwiftUI

/// Width of the leading icon column shared by every settings row, so copy on
/// a second line can align under the title rather than under the icon.
/// Shared with `TrainingSettingsSection`.
let settingsIconColumnWidth: CGFloat = 24

struct AppearanceSettings: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationService = NotificationService.shared
    @State private var biometricService = BiometricService.shared
    @State private var themeManager = ThemeManager.shared
    /// Set when turning protocol reminders on hits a denied permission, so
    /// the toggle bouncing back comes with a route to Settings.
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var store = dataStore
        @Bindable var themeBinding = themeManager

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Preferences", systemImage: "gearshape.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                // Protocol reminders only mean something to someone
                // running a protocol.
                if !dataStore.activeProtocols.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        SettingsToggleRow(
                            icon: "bell.fill",
                            title: "Protocol reminders",
                            subtitle: "Get notified for scheduled doses",
                            isOn: $store.profile.doseRemindersEnabled
                        )
                        .onChange(of: dataStore.profile.doseRemindersEnabled) { _, enabled in
                            handleDoseRemindersToggle(enabled)
                        }

                        if dataStore.profile.doseRemindersEnabled, notificationService.requestedCount > 0 {
                            notificationStatusRow
                        }

                        if notificationsDenied {
                            NotificationsDeniedRow()
                                .padding(.leading, settingsIconColumnWidth + Spacing.md)
                        }
                    }

                    Divider().overlay(AppColor.glassBorder)
                }

                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    title: "Haptic feedback",
                    subtitle: "Vibrate on interactions",
                    isOn: $store.profile.hapticFeedbackEnabled
                )
                .onChange(of: dataStore.profile.hapticFeedbackEnabled) { _, _ in
                    dataStore.persistProfile()
                }

                if biometricService.isAvailable || dataStore.profile.biometricLockEnabled {
                    Divider().overlay(AppColor.glassBorder)

                    SettingsToggleRow(
                        icon: biometricService.biometryIcon,
                        title: "\(biometricService.biometryName) lock",
                        subtitle: "Require \(biometricService.biometryName) to open Atlas.",
                        isOn: $store.profile.biometricLockEnabled
                    )
                    .onChange(of: dataStore.profile.biometricLockEnabled) { _, enabled in
                        handleBiometricLockToggle(enabled)
                    }
                }

                Divider().overlay(AppColor.glassBorder)

                ThemePickerRow(
                    selection: $themeBinding.theme
                )

                Divider().overlay(AppColor.glassBorder)

                DisplayModeRow(selection: $themeBinding.displayMode)

                if AppLanguage.shipped.count > 1 {
                    Divider().overlay(AppColor.glassBorder)

                    LanguagePickerRow()
                }
            }
        }
        .task(id: scenePhase) {
            // Re-checked on return from iOS Settings, so the row clears as
            // soon as the user grants notifications there.
            guard scenePhase == .active, notificationsDenied else { return }
            notificationsDenied = await NotificationService.shared.checkAuthorization() == .denied
        }
    }

    private var notificationStatusRow: some View {
        let limit = NotificationService.pendingRequestLimit
        let overLimit = notificationService.requestedCount > limit
        return HStack(spacing: Spacing.sm) {
            Image(systemName: overLimit ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(AppFont.scaled(11))
                .foregroundStyle(overLimit ? AppColor.warning : AppColor.accentPrimary)

            if overLimit {
                Text("\(notificationService.scheduledCount) of \(notificationService.requestedCount) reminders active (iOS limit: \(limit))")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
            } else {
                Text("^[\(notificationService.scheduledCount) reminder](inflect: true) scheduled")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(.leading, settingsIconColumnWidth + Spacing.md)
    }

    /// Turning the lock on proves the user can pass it first, so nobody
    /// locks themselves behind a check they can't clear.
    private func handleBiometricLockToggle(_ enabled: Bool) {
        guard enabled else {
            dataStore.persistProfile()
            return
        }
        Task {
            if await biometricService.authenticate() {
                dataStore.persistProfile()
            } else {
                dataStore.profile.biometricLockEnabled = false
            }
        }
    }

    private func handleDoseRemindersToggle(_ enabled: Bool) {
        dataStore.persistProfile()
        if enabled {
            Task {
                let authorized = await NotificationService.shared.requestAuthorization()
                notificationsDenied = !authorized
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

struct SettingsToggleRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    /// The label lives inside the `Toggle` so VoiceOver reads the row as
    /// one switch with its title, subtitle and value.
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: settingsIconColumnWidth)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
        .tint(AppColor.accentPrimary)
    }
}

private struct ThemePickerRow: View {
    @Binding var selection: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "paintpalette.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: settingsIconColumnWidth)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Accent color")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(selection.displayName)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()
            }

            HStack(spacing: Spacing.md) {
                ForEach(AppThemeColor.allCases) { theme in
                    swatch(for: theme)
                }
            }
            .padding(.leading, settingsIconColumnWidth + Spacing.md)
        }
    }

    private func swatch(for theme: AppThemeColor) -> some View {
        let isSelected = selection == theme
        return Button {
            guard selection != theme else { return }
            AppAnimation.with(AppAnimation.quick) {
                selection = theme
            }
            Haptics.selection()
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
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(AppColor.onAccent)
                        .opacity(isSelected ? 1 : 0)
                )
                .minimumHitArea()
                .accessibilityLabel(theme.displayName)
                .accessibilityValue(isSelected ? Text("Selected") : Text(verbatim: ""))
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
            GlassSegmentedControl(
                options: DisplayMode.allCases,
                selected: $selection,
                label: { LocalizedStringKey($0.displayName) }
            )
        }
    }
}

/// Shared skeleton for a settings row whose control is wide enough to need
/// its own line beneath the label (matches `ThemePickerRow`'s layout).
/// Also used by `TrainingSettingsSection`.
struct SettingsPickerRow<Control: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: settingsIconColumnWidth)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()
            }

            control()
                .padding(.leading, settingsIconColumnWidth + Spacing.md)
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
