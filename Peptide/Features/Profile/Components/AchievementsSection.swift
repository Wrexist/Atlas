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
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                // Unlocked
                if !unlocked.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(unlocked) { achievement in
                                achievementBadge(achievement, unlocked: true)
                            }
                        }
                    }
                }

                // Next to unlock
                if let next = locked.first {
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
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func achievementBadge(_ achievement: Achievement, unlocked: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: achievement.icon)
                .font(AppFont.scaled(20))
                .foregroundStyle(unlocked ? AppColor.accentLight : AppColor.textTertiary)
                .frame(width: 44, height: 44)
                .background {
                    ZStack {
                        if unlocked {
                            // Outer halo: signals "earned" at thumbnail size on
                            // the App Store listing. The radial fill below sells
                            // the depth — flat opacity reads as decoration.
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            AppColor.accentPrimary.opacity(0.55),
                                            AppColor.accentPrimary.opacity(0.18),
                                            AppColor.accentPrimary.opacity(0.0),
                                        ],
                                        center: .center,
                                        startRadius: 4,
                                        endRadius: 30
                                    )
                                )
                            Circle()
                                .fill(AppColor.accentPrimary.opacity(0.22))
                        } else {
                            Circle().fill(AppColor.surfaceElevated)
                        }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                unlocked ? AppColor.glassBorderActive : AppColor.glassBorder,
                                lineWidth: unlocked ? 1.0 : 0.5
                            )
                    }
                }
                .shadow(
                    color: unlocked ? AppColor.accentGlow : .clear,
                    radius: 6,
                    x: 0,
                    y: 0
                )
                .saturation(unlocked ? 1.0 : 0.35)

            Text(achievement.title)
                .font(AppFont.scaled(9, weight: .medium))
                .foregroundStyle(unlocked ? AppColor.textPrimary : AppColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(width: 64)
    }
}
