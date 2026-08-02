import SwiftUI

struct StackWarningCard: View {
    let warnings: [StackRecommendationEngine.Warning]
    var onSelect: (StackRecommendationEngine.Warning) -> Void

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Stack Alerts", systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(highestSeverityColor)

                VStack(spacing: Spacing.md) {
                    ForEach(warnings) { warning in
                        Button {
                            onSelect(warning)
                        } label: {
                            warningRow(warning)
                        }
                        .buttonStyle(WarningRowPressStyle())

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
        if warnings.contains(where: { $0.severity == .danger }) { return AppColor.destructive }
        if warnings.contains(where: { $0.severity == .caution }) { return AppColor.warning }
        return AppColor.accentPrimary
    }

    private func severityColor(_ severity: StackRecommendationEngine.Warning.Severity) -> Color {
        switch severity {
        case .danger: return AppColor.destructive
        case .caution: return AppColor.warning
        case .info: return AppColor.accentPrimary
        }
    }

    private func warningRow(_ warning: StackRecommendationEngine.Warning) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: warning.icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(severityColor(warning.severity))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(warning.title)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: Spacing.xs)

                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                Text(warning.detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)

                // Actionable suggestion
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .font(AppFont.scaled(9))
                        .foregroundStyle(AppColor.accentLight)
                        .padding(.top, 2)

                    Text(warning.suggestion)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentLight)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(.top, Spacing.xxs)

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(warning.peptides, id: \.self) { name in
                        let color = severityColor(warning.severity)
                        Text(name)
                            .font(AppFont.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(color)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background {
                                Capsule().fill(color.opacity(0.12))
                            }
                    }
                }
                .padding(.top, Spacing.xxs)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct WarningRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(AppAnimation.springSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    Haptics.impact(.light)
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
            ],
            onSelect: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
