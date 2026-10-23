import SwiftUI

/// The one protocol-reminders switch, shared by Settings and the profile
/// sheet so both name it the same and both ask for permission, schedule,
/// and cancel through `ProtocolReminderSwitch`.
struct ProtocolRemindersRow: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationService = NotificationService.shared
    /// Set when turning reminders on hits a denied permission, so the
    /// toggle bouncing back comes with a route to Settings.
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var store = dataStore

        VStack(alignment: .leading, spacing: Spacing.xs) {
            SettingsToggleRow(
                icon: "bell.fill",
                title: "Protocol reminders",
                subtitle: "Get notified for scheduled doses",
                isOn: $store.profile.doseRemindersEnabled
            )
            .onChange(of: dataStore.profile.doseRemindersEnabled) { _, enabled in
                apply(enabled)
            }

            if dataStore.profile.doseRemindersEnabled, notificationService.requestedCount > 0 {
                statusRow
            }

            if notificationsDenied {
                NotificationsDeniedRow()
                    .padding(.leading, settingsIconColumnWidth + Spacing.md)
            }
        }
        .task(id: scenePhase) {
            // Re-checked on return from iOS Settings, so the row clears as
            // soon as the user grants notifications there.
            guard scenePhase == .active, notificationsDenied else { return }
            notificationsDenied = await NotificationService.shared.checkAuthorization() == .denied
        }
    }

    private var statusRow: some View {
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

    private func apply(_ enabled: Bool) {
        dataStore.persistProfile()
        Task {
            let outcome = await ProtocolReminderSwitch.apply(enabled: enabled, effects: .init(
                requestAuthorization: { await NotificationService.shared.requestAuthorization() },
                schedule: { _ = NotificationService.shared.scheduleNotifications(for: dataStore.activeProtocols) },
                // Habit reminders survive this switch: each habit opts in
                // on its own.
                cancel: { NotificationService.shared.cancelProtocolReminders() }
            ))
            guard outcome != .cancelled else { return }
            notificationsDenied = outcome == .denied
            if outcome == .denied {
                // Flipping back re-fires onChange with `false`, which only
                // cancels reminders that were never scheduled.
                dataStore.profile.doseRemindersEnabled = false
                dataStore.persistProfile()
            }
        }
    }
}
