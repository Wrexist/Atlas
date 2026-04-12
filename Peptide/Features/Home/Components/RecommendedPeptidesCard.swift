import SwiftUI

struct RecommendedPeptidesCard: View {
    let recommendations: [StackRecommendationEngine.Recommendation]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Recommended for Your Stack", systemImage: "sparkles")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if recommendations.isEmpty {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColor.textTertiary)

                        Text("Add peptides to a protocol to get smart recommendations")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                } else {
                    VStack(spacing: Spacing.sm) {
                        ForEach(recommendations) { rec in
                            NavigationLink(value: rec.peptide) {
                                recommendationRow(rec)
                            }
                            .buttonStyle(.plain)

                            if rec.id != recommendations.last?.id {
                                Divider().foregroundStyle(AppColor.glassBorder)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recommendationRow(_ rec: StackRecommendationEngine.Recommendation) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rec.peptide.category.color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: rec.peptide.imageSystemName)
                    .font(.system(size: 16))
                    .foregroundStyle(rec.peptide.category.color)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(rec.peptide.abbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    PeptideCategoryBadge(category: rec.peptide.category)
                }

                if let reason = rec.reasons.first {
                    Text(reason)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentLight)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: Spacing.xxs) {
                ForEach(0..<min(rec.score, 5), id: \.self) { _ in
                    Circle()
                        .fill(AppColor.accentPrimary)
                        .frame(width: 4, height: 4)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

#Preview {
    NavigationStack {
        ZStack {
            AppColor.background.ignoresSafeArea()
            RecommendedPeptidesCard(
                recommendations: [
                    .init(
                        id: UUID(),
                        peptide: MockPeptides.bpc157,
                        score: 3,
                        reasons: ["Pairs well with TB-500, GHK-Cu"]
                    ),
                    .init(
                        id: UUID(),
                        peptide: MockPeptides.semax,
                        score: 2,
                        reasons: ["Pairs well with Selank"]
                    ),
                ]
            )
            .padding(Spacing.screenPadding)
        }
    }
    .preferredColorScheme(.dark)
}
