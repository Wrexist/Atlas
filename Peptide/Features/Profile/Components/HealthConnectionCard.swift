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
    var onConnect: () -> Void = {}

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

                (Text("Connect ")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("Apple Health")
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" to sync your health data and get ")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("personalized insights")
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" based on your ")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("wearable metrics")
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(".")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary))
                    .lineSpacing(3)

                if !isConnected {
                    HStack(spacing: Spacing.md) {
                        ForEach(["Heart Rate", "HRV", "Sleep", "Activity"], id: \.self) { metric in
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: iconFor(metric))
                                    .font(AppFont.scaled(16))
                                    .foregroundStyle(colorFor(metric))
                                    .accessibilityHidden(true)
                                Text(metric)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    GlassButton(title: "Connect Apple Health", icon: "heart.fill", style: .primary, isFullWidth: true) {
                        onConnect()
                    }
                } else {
                    nutritionWriteToggle
                }
            }
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
                Text("Logged calories, protein, carbs, fat, and fiber will appear in the Health app's nutrition timeline.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(AppColor.accentPrimary)
    }

    private func iconFor(_ metric: String) -> String {
        switch metric {
        case "Heart Rate": "heart.fill"
        case "HRV": "waveform.path.ecg"
        case "Sleep": "moon.fill"
        case "Activity": "figure.walk"
        default: "circle"
        }
    }

    private func colorFor(_ metric: String) -> Color {
        switch metric {
        case "Heart Rate": AppColor.metricHeartRate
        case "HRV": AppColor.metricHRV
        case "Sleep": AppColor.metricSleep
        case "Activity": AppColor.metricActivity
        default: AppColor.textTertiary
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
