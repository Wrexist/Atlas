import SwiftUI

struct StackCompletenessCard: View {
    let completeness: StackRecommendationEngine.StackCompleteness

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.lg) {
                MetricRing(
                    progress: completeness.score,
                    diameter: 64,
                    strokeWidth: 6,
                    gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                    appearAnimated: true
                ) {
                    Text(completeness.score.formatted(.percent.precision(.fractionLength(0))))
                        .font(AppFont.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Protocol completeness")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    if !completeness.coveredGoals.isEmpty {
                        Text("Covering: \(coveredGoalNames)")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(2)
                    }

                    if let suggestion = completeness.suggestions.first {
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Image(systemName: "lightbulb.fill")
                                .font(AppFont.scaled(8))
                                .foregroundStyle(AppColor.accentLight)
                                .padding(.top, 2)

                            Text(suggestion)
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.accentLight)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Goals are stored as onboarding keys; show their names.
    private var coveredGoalNames: String {
        completeness.coveredGoals
            .map { OnboardingView.PrimaryGoal(rawValue: $0)?.displayName ?? $0 }
            .formatted(.list(type: .and))
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        StackCompletenessCard(
            completeness: .init(
                score: 0.65,
                coveredGoals: ["Muscle Recovery", "Anti-Aging"],
                missingCategories: [.cognitive],
                suggestions: ["Add a Cognitive peptide for your \"Cognitive Enhancement\" goal"]
            )
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
