import SwiftUI

struct ProgressSummaryCard: View {
    let totalDoses: Int
    let compliance: Double
    let currentStreak: Int
    let bestStreak: Int

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Summary", systemImage: "chart.pie.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md),
                ], spacing: Spacing.md) {
                    SummaryStatCell(
                        value: "\(totalDoses)",
                        label: "Total Doses",
                        icon: "syringe.fill",
                        color: AppColor.accentPrimary
                    )

                    SummaryStatCell(
                        value: "\(Int(compliance * 100))%",
                        label: "Compliance",
                        icon: "checkmark.circle.fill",
                        color: AppColor.accentLight
                    )

                    SummaryStatCell(
                        value: "\(currentStreak)",
                        label: "Current Streak",
                        icon: "flame.fill",
                        color: Color(hex: 0xE88D4F)
                    )

                    SummaryStatCell(
                        value: "\(bestStreak)",
                        label: "Best Streak",
                        icon: "trophy.fill",
                        color: Color(hex: 0xD4A844)
                    )
                }
            }
        }
    }
}

private struct SummaryStatCell: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)

            Text(value)
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)

            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(color.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProgressSummaryCard(totalDoses: 127, compliance: 0.82, currentStreak: 12, bestStreak: 18)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
