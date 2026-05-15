import SwiftUI

/// Profile → Settings toggle that controls the AI weekly summary
/// feature. Pro-gated: when the user isn't Pro the row renders in
/// a disabled style with an inline "Pro" badge so the gate reads
/// premium rather than punitive.
///
/// Flipping the toggle off cancels the scheduled Sunday push +
/// suppresses the Today hero card on next render; flipping it
/// back on re-schedules. The toggle binds directly into
/// `dataStore.profile.weeklySummaryEnabled` and persists on every
/// change.
struct WeeklySummaryToggleRow: View {
    @Environment(DataStore.self) private var dataStore
    @State private var storeService = StoreService.shared
    @State private var showPaywall = false

    var body: some View {
        let isPro = storeService.isProUser

        Button {
            if !isPro {
                showPaywall = true
                return
            }
            // Pro user — flip the toggle. Tap on a row outside the
            // switch's hit area still does the right thing; matches
            // the iOS Settings.app interaction model.
            dataStore.profile.weeklySummaryEnabled.toggle()
            dataStore.persistProfile()
            Task { @MainActor in
                await WeeklySummaryNotificationScheduler.reconcile(
                    profile: dataStore.profile,
                    isPro: isPro
                )
            }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text("Weekly recap")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                        if !isPro {
                            Text("PRO")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.5)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background {
                                    Capsule().fill(AppColor.accentPrimary)
                                }
                        }
                    }
                    Text(subtitle(isPro: isPro))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)

                if isPro {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { dataStore.profile.weeklySummaryEnabled },
                            set: { newValue in
                                dataStore.profile.weeklySummaryEnabled = newValue
                                dataStore.persistProfile()
                                Task { @MainActor in
                                    await WeeklySummaryNotificationScheduler.reconcile(
                                        profile: dataStore.profile,
                                        isPro: isPro
                                    )
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .tint(accent)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .liquidGlassPresentation()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(isPro: isPro))
    }

    private var accent: Color {
        Color(red: 0.48, green: 0.50, blue: 0.92)
    }

    private func subtitle(isPro: Bool) -> LocalizedStringKey {
        if !isPro {
            return "Sunday-morning AI recap of your week — Pro feature."
        }
        return dataStore.profile.weeklySummaryEnabled
            ? "Sunday 9 am — recap of compliance, streaks, and patterns."
            : "Toggle on to get the Sunday recap notification."
    }

    private func accessibilityLabel(isPro: Bool) -> String {
        if !isPro {
            return String(localized: "Weekly recap, Pro feature. Double-tap to view subscription options.")
        }
        let state = dataStore.profile.weeklySummaryEnabled
            ? String(localized: "on") : String(localized: "off")
        return String(localized: "Weekly recap, currently \(state)")
    }
}
