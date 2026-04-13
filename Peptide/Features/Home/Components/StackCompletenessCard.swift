import SwiftUI

struct StackCompletenessCard: View {
    let completeness: StackRecommendationEngine.StackCompleteness

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.lg) {
                GlassProgressRing(
                    progress: completeness.score,
                    size: 64,
                    lineWidth: 6,
                    showLabel: false
                )
                .overlay {
                    Text("\(Int(completeness.score * 100))%")
                        .font(AppFont.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)
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
                                .font(.system(size: 9))
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
