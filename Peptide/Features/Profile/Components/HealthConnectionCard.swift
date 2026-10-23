import SwiftUI

struct HealthConnectionCard: View {
    let isConnected: Bool
    /// Whether the user has opted in to writing logged meals back to
    /// Apple Health (calories, protein, carbs, fat, fiber). Only
    /// shown once `isConnected` is true so the card stays focused on
    /// the read connection during onboarding.
    var nutritionWriteEnabled: Bool = false
    /// Fires when the user flips the nutrition-write toggle. Caller
    /// is responsible for requesting HK write permission and only
    /// flipping the underlying state once granted — pass-through
    /// because the request is async.
    var onToggleNutritionWrite: (Bool) -> Void = { _ in }
    /// Whether finished workouts, weigh-ins and water are mirrored to
    /// Apple Health, and scale weigh-ins read back. Same async
    /// pass-through as the meal toggle.
    var activitySyncEnabled: Bool = false
    var onToggleActivitySync: (Bool) -> Void = { _ in }
    /// True after turning a write toggle on came back without access.
    var writeAccessRefused: Bool = false
    /// Awaited so the button can show it's waiting on HealthKit's
    /// permission sheet rather than sitting idle under it.
    var onConnect: @MainActor () async -> Void = {}

    @State private var isConnecting = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(isConnected ? AppColor.accentPrimary : AppColor.textTertiary)
                            .frame(width: 8, height: 8)

                        Text(isConnected ? "Connected" : "Not Connected")
                            .font(AppFont.caption2)
                            .foregroundStyle(isConnected ? AppColor.accentLight : AppColor.textTertiary)
                    }
                }

                Text("Connect Apple Health to bring heart rate, HRV, sleep and activity into your recovery score.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isConnected {
                    HStack(spacing: Spacing.md) {
                        ForEach(HealthPreviewMetric.allCases, id: \.self) { metric in
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: metric.icon)
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(metric.color)
                                    .accessibilityHidden(true)
                                Text(metric.title)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    GlassButton(
                        title: isConnecting ? "Connecting…" : "Connect Apple Health",
                        icon: "heart.fill",
                        style: .primary,
                        isFullWidth: true
                    ) {
                        Task {
                            isConnecting = true
                            await onConnect()
                            isConnecting = false
                        }
                    }
                    .disabled(isConnecting)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        syncToggle(
                            title: "Sync workouts, weight and water",
                            detail: "Finished workouts, weigh-ins and water show up in the Health app, and weigh-ins from a smart scale come back to Atlas.",
                            isOn: activitySyncEnabled,
                            onChange: onToggleActivitySync
                        )
                        syncToggle(
                            title: "Write meals to Apple Health",
                            detail: "Logged calories, protein, carbs and fat will appear in the Health app's nutrition timeline.",
                            isOn: nutritionWriteEnabled,
                            onChange: onToggleNutritionWrite
                        )
                        if writeAccessRefused {
                            Text("Atlas isn't allowed to write to Apple Health. Turn it on in Settings › Health › Data Access & Devices › Atlas.")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .appAnimation(AppAnimation.springSmooth, value: isConnected)
        }
        .onChange(of: isConnected) { _, connected in
            if connected { Haptics.success() }
        }
    }

    /// Inline write toggles exposed once the user has connected, so
    /// Atlas plays well with the rest of the user's health stack. Both
    /// are off by default.
    private func syncToggle(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(AppColor.accentPrimary)
    }
}

/// The Apple Health metrics previewed before the user connects.
private enum HealthPreviewMetric: CaseIterable {
    case heartRate, hrv, sleep, activity

    var title: LocalizedStringKey {
        switch self {
        case .heartRate: "Heart Rate"
        case .hrv: "HRV"
        case .sleep: "Sleep"
        case .activity: "Activity"
        }
    }

    var icon: String {
        switch self {
        case .heartRate: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .sleep: "moon.fill"
        case .activity: "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: AppColor.metricHeartRate
        case .hrv: AppColor.metricHRV
        case .sleep: AppColor.metricSleep
        case .activity: AppColor.metricActivity
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            HealthConnectionCard(isConnected: false)
            HealthConnectionCard(isConnected: true)
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
