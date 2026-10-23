import SwiftUI

struct CycleTransitionCard: View {
    let transitions: [StackRecommendationEngine.CycleTransition]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Cycle transitions", systemImage: "arrow.triangle.2.circlepath")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: Spacing.md) {
                    ForEach(transitions) { transition in
                        transitionRow(transition)

                        if transition.id != transitions.last?.id {
                            Divider().overlay(AppColor.glassBorder)
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
                .font(AppFont.scaled(13))
                .foregroundStyle(transition.weeksRemaining == 0 ? AppColor.warning : AppColor.accentPrimary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(transition.peptideAbbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(transition.weeksRemaining == 0 ? "Cycle complete" : "^[\(transition.weeksRemaining) week](inflect: true) left")
                        .font(AppFont.badge)
                        .foregroundStyle(transition.weeksRemaining == 0 ? AppColor.warning : AppColor.accentLight)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(
                                (transition.weeksRemaining == 0 ? AppColor.warning : AppColor.accentLight).opacity(0.15)
                            )
                        }
                }

                Text(transition.reason)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(2)

                // Information, not an instruction: Atlas doesn't
                // recommend or prescribe compounds.
                if !transition.suggestedReplacements.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(AppColor.accentLight)
                            .accessibilityHidden(true)

                        Text("Often rotated with \(transition.suggestedReplacements.formatted(.list(type: .or))). Discuss changes with a qualified clinician.")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.accentLight)
                            .fixedSize(horizontal: false, vertical: true)
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
