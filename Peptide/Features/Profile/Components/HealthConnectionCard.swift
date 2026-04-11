import SwiftUI

struct HealthConnectionCard: View {
    let isConnected: Bool

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

                Text("Connect Apple Health to sync your health data and get personalized insights based on your wearable metrics.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(3)

                if !isConnected {
                    HStack(spacing: Spacing.md) {
                        ForEach(["Heart Rate", "HRV", "Sleep", "Activity"], id: \.self) { metric in
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: iconFor(metric))
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColor.textTertiary)
                                Text(metric)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    GlassButton(title: "Connect Apple Health", icon: "heart.fill", style: .primary, isFullWidth: true) {}
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
