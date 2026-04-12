import SwiftUI

struct HealthConnectionCard: View {
    let isConnected: Bool
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" to sync your health data and get ")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("personalized insights")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" based on your ")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("wearable metrics")
                    .font(.system(size: 15, weight: .medium))
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
                                    .font(.system(size: 16))
                                    .foregroundStyle(colorFor(metric))
                                Text(metric)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    VStack(spacing: Spacing.xs) {
                        GlassButton(title: "Connect Apple Health", icon: "heart.fill", style: .primary, isFullWidth: true) {
                            onConnect()
                        }

                        Text("Coming soon")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
            }
        }
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
        case "Heart Rate": Color(hex: 0xCF7272)
        case "HRV": Color(hex: 0x9B72CF)
        case "Sleep": Color(hex: 0xD4A844)
        case "Activity": Color(hex: 0x4A7C59)
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
