import SwiftUI

struct RecommendedPeptidesCard: View {
    let recommendations: [StackRecommendationEngine.Recommendation]
    var hapticEnabled: Bool = true

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
                            .buttonStyle(RecommendationPressStyle(hapticEnabled: hapticEnabled))

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

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(rec.peptide.abbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    PeptideCategoryBadge(category: rec.peptide.category)

                    // Synergy tag if present
                    if rec.reasons.contains(where: { if case .categorySynergy = $0 { return true }; return false }) {
                        Text("Synergy")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColor.accentPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                            }
                    }
                }

                // Show up to 2 reasons with icons
                ForEach(Array(rec.reasons.prefix(2).enumerated()), id: \.offset) { _, reason in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: reason.icon)
                            .font(.system(size: 8))
                            .foregroundStyle(AppColor.accentLight)

                        Text(reason.text)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

private struct RecommendationPressStyle: ButtonStyle {
    var hapticEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppAnimation.springSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && hapticEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
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
                        score: 5,
                        reasons: [
                            .commonStack(pairsWith: ["TB-500", "GHK-Cu"]),
                            .goalMatch(goal: "recovery"),
                            .categorySynergy(description: "Growth + Recovery amplify tissue repair"),
                        ]
                    ),
                    .init(
                        id: UUID(),
                        peptide: MockPeptides.semax,
                        score: 3,
                        reasons: [
                            .commonStack(pairsWith: ["Selank"]),
                            .goalMatch(goal: "cognitive"),
                        ]
                    ),
                ]
            )
            .padding(Spacing.screenPadding)
        }
    }
    .preferredColorScheme(.dark)
}
