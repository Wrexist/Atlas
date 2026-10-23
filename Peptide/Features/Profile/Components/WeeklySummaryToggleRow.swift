import SwiftUI

/// Settings toggle for the AI weekly summary. Pro users get a real
/// `Toggle`, so VoiceOver reads it as a switch with a value; free users get
/// a button with the Pro badge that opens the paywall.
///
/// Flipping it off cancels the scheduled Sunday push and suppresses the
/// Today hero card on next render; flipping it back on re-schedules.
struct WeeklySummaryToggleRow: View {
    @Environment(DataStore.self) private var dataStore
    @State private var storeService = StoreService.shared
    @State private var showPaywall = false

    /// The next Sunday 9:00 delivery — matches
    /// `WeeklySummaryNotificationScheduler` — formatted per locale so
    /// 24-hour clocks read "09:00".
    private static var deliveryTime: Date {
        Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 9, minute: 0, weekday: 1),
            matchingPolicy: .nextTime
        ) ?? .now
    }

    var body: some View {
        Group {
            if storeService.isProUser {
                Toggle(isOn: Binding(
                    get: { dataStore.profile.weeklySummaryEnabled },
                    set: setEnabled
                )) {
                    label(isPro: true)
                }
                .tint(AppColor.recap)
                .padding(Spacing.md)
                .insetRowBackground()
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        label(isPro: false)
                        Spacer(minLength: Spacing.sm)
                        Image(systemName: "lock.fill")
                            .font(AppFont.scaled(13, weight: .heavy))
                            .foregroundStyle(AppColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(Spacing.md)
                    .insetRowBackground()
                    .contentShape(.rect)
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                .accessibilityLabel("Weekly recap, Pro feature")
                .accessibilityHint("Opens subscription options.")
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .weeklyRecap)
                .liquidGlassPresentation()
        }
    }

    private func label(isPro: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(AppFont.scaled(16, weight: .heavy))
                .foregroundStyle(AppColor.recap)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.recap.opacity(0.18))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text("Weekly recap")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    if !isPro {
                        ProBadge()
                    }
                }
                subtitle(isPro: isPro)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .appAnimation(AppAnimation.fadeIn, value: dataStore.profile.weeklySummaryEnabled)
            }
        }
    }

    private func subtitle(isPro: Bool) -> Text {
        if !isPro {
            return Text("Sunday-morning AI recap of your week — Pro feature.")
        }
        return dataStore.profile.weeklySummaryEnabled
            ? Text("\(Self.deliveryTime, format: .dateTime.weekday(.wide).hour().minute()) — a recap of your training, nutrition and recovery.")
            : Text("Off. Turning it on sends weekly totals and your HRV trend to Anthropic's Claude to write the recap.")
    }

    private func setEnabled(_ enabled: Bool) {
        dataStore.profile.weeklySummaryEnabled = enabled
        if enabled { dataStore.profile.weeklySummaryOptInConfirmed = true }
        dataStore.persistProfile()
        Task { @MainActor in
            await WeeklySummaryNotificationScheduler.reconcile(
                dataStore: dataStore,
                isPro: storeService.isProUser
            )
        }
    }
}
