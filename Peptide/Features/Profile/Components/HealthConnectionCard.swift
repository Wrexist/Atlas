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
                            .font(AppFont.caption)
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
                                    .font(AppFont.caption)
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
                    nutritionWriteToggle
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .appAnimation(AppAnimation.springSmooth, value: isConnected)
        }
        .onChange(of: isConnected) { _, connected in
            if connected { Haptics.success() }
        }
    }

    /// Inline toggle exposed once the user has connected. Lets logged
    /// meals (food library + barcode scan + photo scan) mirror into
    /// Apple Health's nutrition timeline so Atlas plays well with
    /// the rest of the user's health stack. Off by default.
    private var nutritionWriteToggle: some View {
        Toggle(isOn: Binding(
            get: { nutritionWriteEnabled },
            set: { onToggleNutritionWrite($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Write meals to Apple Health")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Logged calories, protein, carbs and fat will appear in the Health app's nutrition timeline.")
                    .font(AppFont.caption)
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
