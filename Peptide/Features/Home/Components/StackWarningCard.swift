import SwiftUI

struct StackWarningCard: View {
    let warnings: [StackRecommendationEngine.Warning]

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Stack Alerts", systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(highestSeverityColor)

                VStack(spacing: Spacing.md) {
                    ForEach(warnings) { warning in
                        warningRow(warning)

                        if warning.id != warnings.last?.id {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var highestSeverityColor: Color {
        warnings.contains(where: { $0.severity == .danger })
            ? AppColor.destructive
            : Color.orange
    }

    private func warningRow(_ warning: StackRecommendationEngine.Warning) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: warning.icon)
                .font(.system(size: 14))
                .foregroundStyle(warning.severity == .danger ? AppColor.destructive : Color.orange)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(warning.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)

                Text(warning.detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(2)

                // Actionable suggestion
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColor.accentLight)
                        .padding(.top, 2)

                    Text(warning.suggestion)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentLight)
                        .lineSpacing(2)
                }
                .padding(.top, Spacing.xxs)

                HStack(spacing: Spacing.xs) {
                    ForEach(warning.peptides, id: \.self) { name in
                        Text(name)
                            .font(AppFont.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(warning.severity == .danger ? AppColor.destructive : Color.orange)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background {
                                Capsule()
                                    .fill((warning.severity == .danger ? AppColor.destructive : Color.orange).opacity(0.12))
                            }
                    }
                }
                .padding(.top, Spacing.xxs)
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        StackWarningCard(
            warnings: [
                .init(
                    severity: .danger,
                    title: "Potential interaction",
                    detail: "CJC-1295 and Sermorelin may have contraindications when combined.",
                    suggestion: "Review both peptides' safety profiles and consult a professional before combining.",
                    peptides: ["CJC-1295", "Sermorelin"],
                    icon: "xmark.octagon.fill"
                ),
                .init(
                    severity: .caution,
                    title: "Redundant GHS-R agonists",
                    detail: "Ipamorelin & GHRP-6 target the same ghrelin receptor. Risk of desensitization.",
                    suggestion: "Keep one GHS-R agonist and pair with a GHRH analog for synergistic GH release.",
                    peptides: ["Ipamorelin", "GHRP-6"],
                    icon: "arrow.triangle.2.circlepath"
                ),
                .init(
                    severity: .caution,
                    title: "High injection burden",
                    detail: "Your stack requires ~6 injections daily across 5 peptides.",
                    suggestion: "Group compatible peptides at the same injection time to reduce needle count.",
                    peptides: ["BPC-157", "TB-500", "CJC-1295", "Ipamorelin", "IGF-1"],
                    icon: "syringe.fill"
                ),
            ]
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
