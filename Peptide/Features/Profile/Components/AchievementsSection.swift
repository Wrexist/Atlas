import SwiftUI

struct AchievementsSection: View {
    let achievements: [Achievement]

    private var unlocked: [Achievement] { achievements.filter(\.isUnlocked) }
    private var locked: [Achievement] { achievements.filter { !$0.isUnlocked } }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Achievements", systemImage: "trophy.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    Spacer()

                    Text("\(unlocked.count)/\(achievements.count)")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .contentTransition(.numericText())
                        .appAnimation(AppAnimation.springSnappy, value: unlocked.count)
                }

                if !unlocked.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(unlocked) { achievement in
                                achievementBadge(achievement)
                                    .scrollTransition { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                            .opacity(phase.isIdentity ? 1 : 0.6)
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }

                if !achievements.isEmpty && locked.isEmpty {
                    Label("All achievements unlocked", systemImage: "checkmark.seal.fill")
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.achievement)
                } else if let next = locked.first {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: next.icon)
                            .font(AppFont.scaled(16))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(AppColor.surfaceElevated)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                    }
                            }

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Next: \(next.title)")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Text(next.description)
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        VStack(spacing: Spacing.xs) {
            MilestoneArtwork(
                symbol: achievement.icon,
                tint: AppColor.achievement,
                size: 56,
                isActive: false
            )

            Text(achievement.title)
                .font(AppFont.badgeSmall)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Achievement: \(achievement.title)")
        .accessibilityValue(achievement.description)
    }
}
