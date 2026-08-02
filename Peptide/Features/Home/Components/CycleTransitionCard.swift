import SwiftUI

struct CycleTransitionCard: View {
    let transitions: [StackRecommendationEngine.CycleTransition]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Cycle Transitions", systemImage: "arrow.triangle.2.circlepath")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: Spacing.md) {
                    ForEach(transitions) { transition in
                        transitionRow(transition)

                        if transition.id != transitions.last?.id {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transitionRow(_ transition: StackRecommendationEngine.CycleTransition) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: transition.weeksRemaining == 0 ? "exclamationmark.circle.fill" : "clock.fill")
                .font(AppFont.scaled(14))
                .foregroundStyle(transition.weeksRemaining == 0 ? Color.orange : AppColor.accentPrimary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(transition.peptideAbbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(transition.weeksRemaining == 0 ? "Cycle complete" : "\(transition.weeksRemaining)w remaining")
                        .font(AppFont.scaled(9, weight: .bold))
                        .foregroundStyle(transition.weeksRemaining == 0 ? Color.orange : AppColor.accentLight)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(
                                (transition.weeksRemaining == 0 ? Color.orange : AppColor.accentLight).opacity(0.15)
                            )
                        }
                }

                Text(transition.reason)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(2)

                if !transition.suggestedReplacements.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.right.circle")
                            .font(AppFont.scaled(9))
                            .foregroundStyle(AppColor.accentLight)

                        Text("Switch to: \(transition.suggestedReplacements.joined(separator: " or "))")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        CycleTransitionCard(
            transitions: [
                .init(
                    peptideAbbreviation: "CJC-1295 DAC",
                    weeksRemaining: 0,
                    suggestedReplacements: ["Mod GRF 1-29", "Sermorelin"],
                    reason: "Prevents pituitary desensitization to GHRH signaling"
                ),
                .init(
                    peptideAbbreviation: "Ipamorelin",
                    weeksRemaining: 1,
                    suggestedReplacements: ["GHRP-2"],
                    reason: "GHS-R receptor sensitivity maintenance"
                ),
            ]
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
