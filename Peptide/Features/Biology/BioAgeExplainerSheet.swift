import SwiftUI

/// What the number on the dial actually means, reachable from the info
/// button under it. The estimate is directional rather than clinical, and
/// a user who can't see how it was built has no reason to act on it — so
/// this names the four signals, the anchor, and the cap, in that order.
struct BioAgeExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Signal: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        var id: String { icon }
    }

    private let signals: [Signal] = [
        .init(icon: "heart",
              title: "Heart rate variability",
              detail: "Your 30-day median. Higher variability reads as a better-recovered nervous system."),
        .init(icon: "waveform.path.ecg",
              title: "Resting heart rate",
              detail: "Your 30-day median. A lower resting rate tracks with aerobic fitness."),
        .init(icon: "moon.fill",
              title: "Sleep",
              detail: "Median hours asleep per night. Both too little and too much move the estimate."),
        .init(icon: "scalemass.fill",
              title: "Weight trend",
              detail: "The direction your weight moved over 30 days, not the number itself."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Your Bio Age starts at your real age, then moves up or down with four signals Atlas reads from Health.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)

                    VStack(spacing: Spacing.sm) {
                        ForEach(signals) { signal in
                            signalRow(signal)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("What it won't do")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("The estimate never drifts more than \(Int(PerformanceAgeEngine.maxDriftYears)) years from your chronological age, and Atlas won't show a number at all until it has at least \(BioAgeStateResolver.minBaselineDays) days of data behind it. One good week shouldn't be able to claim a decade.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Text("Atlas estimates based on your personal biometrics. Not medical advice.")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("How Bio Age works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func signalRow(_ signal: Signal) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: signal.icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                        .fill(AppColor.glassTint)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(signal.detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BioAgeExplainerSheet()
}
