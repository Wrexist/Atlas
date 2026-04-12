import SwiftUI

struct InsightsCard: View {
    let insights: [InsightEngine.Insight]

    var body: some View {
        if !insights.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label("Insights", systemImage: "lightbulb.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    ForEach(Array(insights.prefix(3).enumerated()), id: \.element.id) { index, insight in
                        HStack(alignment: .top, spacing: Spacing.md) {
                            Image(systemName: insight.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(iconColor(for: insight.type))
                                .frame(width: 28, height: 28)
                                .background {
                                    Circle()
                                        .fill(iconColor(for: insight.type).opacity(0.15))
                                }

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(insight.title)
                                    .font(AppFont.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppColor.textPrimary)

                                Text(insight.description)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineSpacing(2)
                            }
                        }

                        if index < min(insights.count, 3) - 1 {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                    }
                }
            }
        }
    }

    private func iconColor(for type: InsightEngine.InsightType) -> Color {
        switch type {
        case .positive: return AppColor.accentPrimary
        case .warning: return AppColor.warning
        case .neutral: return AppColor.textSecondary
        }
    }
}
