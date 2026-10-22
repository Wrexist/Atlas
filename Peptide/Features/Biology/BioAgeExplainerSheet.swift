import SwiftUI

/// What the number on the dial actually means, reachable from the info
/// button under it. The estimate is directional rather than clinical, and
/// a user who can't see how it was built has no reason to act on it — so
/// this names the signals, the anchor, and the cap, in that order.
struct BioAgeExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let signals = PerformanceAgeEngine.Driver.Kind.allCases

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Your Biological Age starts at your real age, then moves up or down with up to \(signals.count) signals from Apple Health and your profile. Each one can only move it a few years.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)

                    VStack(spacing: Spacing.sm) {
                        ForEach(signals, id: \.self) { kind in
                            signalRow(kind)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Confidence")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Cardio fitness, HRV and resting heart rate count most toward confidence, because they track ageing most closely. Confidence also grows with each day of heart and sleep data, up to \(PerformanceAgeEngine.windowDays) days.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("What it won't do")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("The estimate never drifts more than \(Int(PerformanceAgeEngine.maxDriftYears)) years from your chronological age, and Atlas won't show a number at all until it has at least \(BioAgeStateResolver.minBaselineDays) days of data and enough signals behind it. One good week shouldn't be able to claim a decade.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Text("Atlas estimates based on your personal biometrics. It's a direction to watch, not a medical test, and not medical advice.")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                .readableContentWidth()
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("How Biological Age works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func signalRow(_ kind: PerformanceAgeEngine.Driver.Kind) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: kind.icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(kind.tint)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                        .fill(kind.tint.opacity(0.15))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(kind.displayName)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(kind.explanation)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Up to \(BioAgeFormat.age(kind.maxSwingYears)) years")
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textSecondary)
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
