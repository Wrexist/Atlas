import SwiftUI

/// Profile's read of the Atlas Score: the level ring filling toward the
/// next level, and the numbers behind it. Unlike Today's `AtlasScoreCard`
/// it carries no tier colour or streak ink, so the page keeps one accent.
/// Tapping opens the full progress view, where the badges live.
struct ProfileLevelCard: View {
    @Environment(DataStore.self) private var dataStore
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) { card }
            .buttonStyle(ScalePressStyle())
            .accessibilityHint("Opens your progress")
    }

    private var card: some View {
        let momentum = dataStore.momentum

        return HStack(spacing: Spacing.lg) {
            MetricRing(
                progress: momentum.progressInLevel,
                diameter: 64,
                strokeWidth: 6,
                gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                appearAnimated: true
            ) {
                VStack(spacing: 0) {
                    Text("LV")
                        .font(AppFont.eyebrow)
                        .foregroundStyle(AppColor.textTertiary)
                    Text("\(momentum.level)")
                        .font(AppFont.scaled(24, weight: .medium, relativeTo: .title1))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Atlas Score")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Level \(momentum.level) · \(momentum.score) pts")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .contentTransition(.numericText())
                Text("\(momentum.pointsToNextLevel) to level \(momentum.level + 1)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "Atlas Score: level \(momentum.level), \(momentum.tier.name) tier, \(momentum.score) points. \(momentum.pointsToNextLevel) to the next level."
        ))
    }
}
