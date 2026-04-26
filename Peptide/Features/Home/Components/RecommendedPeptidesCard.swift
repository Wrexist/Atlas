import SwiftUI

struct RecommendedPeptidesCard: View {
    let recommendations: [StackRecommendationEngine.Recommendation]
    var activeProtocols: [PeptideProtocol] = []
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
                                recommendationRow(rec, stacks: stacks(for: rec.peptide))
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

    private func stacks(for peptide: Peptide) -> [PeptideProtocol] {
        activeProtocols.filter { proto in
            proto.peptides.contains(where: { $0.id == peptide.id })
        }
    }

    private func reasonBadge(_ text: String, color: Color, bgOpacity: Double) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background { Capsule().fill(color.opacity(bgOpacity)) }
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: StackRecommendationEngine.Confidence) -> some View {
        switch confidence {
        case .high:
            reasonBadge("Research-backed", color: AppColor.accentLight, bgOpacity: 0.2)
        case .medium:
            reasonBadge("Suggested", color: AppColor.accentPrimary, bgOpacity: 0.15)
        case .low:
            reasonBadge("Exploratory", color: AppColor.textSecondary, bgOpacity: 0.1)
        }
    }

    private func recommendationRow(
        _ rec: StackRecommendationEngine.Recommendation,
        stacks: [PeptideProtocol]
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
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

                    confidenceBadge(rec.confidence)
                }

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

                stackMembership(stacks)
            }

            Spacer(minLength: 0)

            trailingAffordance(inStacks: !stacks.isEmpty)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func stackMembership(_ stacks: [PeptideProtocol]) -> some View {
        if !stacks.isEmpty {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColor.accentLight)

                ForEach(Array(stacks.prefix(2).enumerated()), id: \.element.id) { index, proto in
                    stackPill(proto.name)
                    if index < min(stacks.count, 2) - 1 {
                        Text("·")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }

                if stacks.count > 2 {
                    Text("+\(stacks.count - 2)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func stackPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AppColor.accentLight)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .overlay {
                        Capsule()
                            .strokeBorder(AppColor.accentPrimary.opacity(0.3), lineWidth: 0.5)
                    }
            }
            .liquidGlass(.capsule)
    }

    @ViewBuilder
    private func trailingAffordance(inStacks: Bool) -> some View {
        ZStack {
            Circle()
                .fill(AppColor.accentPrimary.opacity(inStacks ? 0.12 : 0.22))
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }

            Image(systemName: inStacks ? "chevron.right" : "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
        }
        .liquidGlass(.circle)
        .padding(.top, 4)
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
                        ],
                        confidence: .high
                    ),
                    .init(
                        id: UUID(),
                        peptide: MockPeptides.semax,
                        score: 3,
                        reasons: [
                            .commonStack(pairsWith: ["Selank"]),
                            .goalMatch(goal: "cognitive"),
                        ],
                        confidence: .medium
                    ),
                ],
                activeProtocols: MockProtocols.all
            )
            .padding(Spacing.screenPadding)
        }
    }
    .preferredColorScheme(.dark)
}
