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
                    appearAnimated: true,
                    glow: true
                ) {
                    Text("\(Int(completeness.score * 100))%")
                        .font(AppFont.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Stack Completeness")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    if !completeness.coveredGoals.isEmpty {
                        Text("Covering: \(completeness.coveredGoals.joined(separator: ", "))")
                            .font(AppFont.caption)
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
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.accentLight)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()
            }
        }
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
