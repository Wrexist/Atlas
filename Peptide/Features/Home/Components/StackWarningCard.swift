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
            Image(systemName: warning.severity == .danger
                  ? "xmark.octagon.fill"
                  : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 14))
            .foregroundStyle(warning.severity == .danger ? AppColor.destructive : Color.orange)
            .frame(width: 20)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(warning.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)

                Text(warning.detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(2)

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
                    detail: "CJC-1295 and Sermorelin may have contraindications when used together.",
                    peptides: ["CJC-1295", "Sermorelin"]
                ),
                .init(
                    severity: .caution,
                    title: "Compounding side effect risk",
                    detail: "3 peptides share \"nausea\" as a potential side effect. Monitor closely.",
                    peptides: ["BPC-157", "TB-500", "GHK-Cu"]
                ),
            ]
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
