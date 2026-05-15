import SwiftUI

/// Reusable floating callout used to surface a single high-signal
/// `InsightEngine.Insight` directly on a chart or heatmap. Slot 5 of
/// the App Store screenshot deck pins one of these to the
/// `CalendarHeatmap` so the "Tuesdays slip" annotation reads as live UI
/// rather than a Figma overlay.
///
/// Tints itself by `InsightType` so colour does the work of priority:
/// warning = amber, positive = emerald, neutral = surface.
struct InsightBubble: View {
    let insight: InsightEngine.Insight

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: insight.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(iconColor.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(insight.description)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(backgroundFill)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                }
        }
    }

    private var iconColor: Color {
        switch insight.type {
        case .positive: AppColor.accentPrimary
        case .warning: AppColor.warning
        case .neutral: AppColor.textSecondary
        }
    }

    private var backgroundFill: Color {
        switch insight.type {
        case .positive: AppColor.accentPrimary.opacity(0.10)
        case .warning: AppColor.warning.opacity(0.10)
        case .neutral: AppColor.surfaceElevated
        }
    }

    private var borderColor: Color {
        switch insight.type {
        case .positive: AppColor.glassBorderActive
        case .warning: AppColor.warning.opacity(0.30)
        case .neutral: AppColor.glassBorder
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            InsightBubble(insight: .init(
                icon: "calendar.badge.exclamationmark",
                title: "Pattern detected",
                description: "You tend to miss doses on Tuesdays. Consider setting an extra reminder.",
                type: .warning
            ))
            InsightBubble(insight: .init(
                icon: "flame.fill",
                title: "Strong streak!",
                description: "23 days in a row. Keep the momentum going.",
                type: .positive
            ))
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
