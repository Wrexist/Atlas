import SwiftUI
import UserNotifications

/// Settings → Reminders. One row per daily nudge (weigh-in, the three
/// meals, training days), each with its own time. Turning the first one
/// on asks for notification permission; every change re-plans the
/// pending requests through `DailyReminderScheduler`.
struct DailyRemindersSection: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = DailyReminderSettings.defaults(training: nil)
    @State private var permissionDenied = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Label("Reminders", systemImage: "bell.badge.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Each one stays quiet on days you've already logged it.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                if permissionDenied {
                    NotificationsDeniedRow()
                }

                ForEach(Array(DailyReminderKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 {
                        Divider().overlay(AppColor.glassBorder)
                    }
                    DailyReminderRow(
                        kind: kind,
                        subtitle: subtitle(for: kind),
                        slot: binding(for: kind)
                    )
                }

                // Every notification switch lives in this one card; protocol
                // reminders only mean something to someone running one.
                if !dataStore.activeProtocols.isEmpty {
                    Divider().overlay(AppColor.glassBorder)

                    ProtocolRemindersRow()
                }
            }
        }
        .task {
            settings = DailyReminderSettings.load(training: dataStore.profile.trainingPreferences)
        }
        .task(id: scenePhase) {
            // Re-checked on return from iOS Settings, so the banner clears
            // as soon as the user grants notifications there.
            guard scenePhase == .active else { return }
            permissionDenied = await NotificationService.shared.checkAuthorization() == .denied
        }
    }

    private func subtitle(for kind: DailyReminderKind) -> LocalizedStringKey {
        switch kind {
        case .weighIn:
            "Reply with your weight right from the notification"
        case .breakfast, .lunch, .dinner:
            "Scan it, or repeat yesterday's in one tap"
        case .workout:
            trainingDaysSubtitle
        }
    }

    private var trainingDaysSubtitle: LocalizedStringKey {
        let days = dataStore.profile.trainingPreferences?.preferredDays ?? []
        guard !days.isEmpty else { return "Every day — pick training days in your plan" }
        let names = Weekday.allCases.filter(days.contains).map(\.shortName).joined(separator: " · ")
        return "\(names)"
    }

    private func binding(for kind: DailyReminderKind) -> Binding<DailyReminderSettings.Slot> {
        Binding(
            get: { settings.slot(kind) },
            set: { newSlot in
                let turnedOn = newSlot.isEnabled && !settings.slot(kind).isEnabled
                settings.slots[kind] = newSlot
                settings.save()
                Task { @MainActor in
                    if turnedOn {
                        permissionDenied = !(await NotificationService.shared.requestAuthorization())
                        // A denied permission means this reminder can't
                        // fire, so the toggle shouldn't claim it's on.
                        if permissionDenied {
                            settings.slots[kind]?.isEnabled = false
                            settings.save()
                        }
                    }
                    await DailyReminderScheduler.reconcile(dataStore: dataStore)
                }
            }
        )
    }
}

private struct DailyReminderRow: View {
    let kind: DailyReminderKind
    let subtitle: LocalizedStringKey
    @Binding var slot: DailyReminderSettings.Slot

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: kind.systemImage)
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: settingsIconColumnWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(kind.displayName)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            if slot.isEnabled {
                DatePicker(
                    kind.displayName,
                    selection: time,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .transition(.opacity)
            }

            Toggle(kind.displayName, isOn: enabled)
                .labelsHidden()
                .tint(AppColor.accentPrimary)
        }
        .appAnimation(AppAnimation.quick, value: slot.isEnabled)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { slot.isEnabled },
            set: { slot.isEnabled = $0 }
        )
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                slot.hour = parts.hour ?? slot.hour
                slot.minute = parts.minute ?? slot.minute
            }
        )
    }
}

/// Shown wherever a reminder toggle needs notification permission the
/// user has denied: iOS won't ask twice, so Settings is the only route.
/// Shared with `ProtocolRemindersRow`.
struct NotificationsDeniedRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.warning)
                Text("Notifications are off for Atlas. Turn them on in Settings.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        DailyRemindersSection()
            .padding(Spacing.screenPadding)
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
