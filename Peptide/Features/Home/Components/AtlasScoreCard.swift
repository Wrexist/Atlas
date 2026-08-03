import SwiftUI

/// Today's "Atlas Score" showcase — the earned level ring, prestige tier,
/// lifetime score, and points banked today. Reads the cheap
/// `dataStore.momentum` snapshot (pure arithmetic over stored profile
/// state, safe in a body). This is the "you're improving" identity the
/// rest of the motivation system feeds.
struct AtlasScoreCard: View {
    @Environment(DataStore.self) private var dataStore
    /// When set, the card becomes tappable (opens the progress surface)
    /// and shows a trailing chevron.
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { card }
                .buttonStyle(ScalePressStyle())
                .accessibilityHint("Opens your progress")
        } else {
            card
        }
    }

    private var card: some View {
        let momentum = dataStore.momentum
        let tint = Color(hex: UInt(momentum.tier.tintHex))

        return HStack(spacing: Spacing.lg) {
            MetricRing(
                progress: momentum.progressInLevel,
                diameter: 72,
                strokeWidth: 8,
                gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                appearAnimated: true
            ) {
                VStack(spacing: 0) {
                    Text("LV")
                        .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textSecondary)
                    Text("\(momentum.level)")
                        .font(AppFont.scaled(26, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: 6) {
                    Image(systemName: momentum.tier.symbol)
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(tint)
                    Text("\(momentum.tier.name) · Atlas Score")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }
                Text("\(momentum.score) pts")
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .contentTransition(.numericText())
                Text(progressLine(momentum))
                    .font(AppFont.caption)
                    .foregroundStyle(momentum.todayEarned > 0 ? AppColor.streak : AppColor.textTertiary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Atlas Score: level \(momentum.level), \(momentum.tier.name) tier, "
            + "\(momentum.score) points. \(momentum.pointsToNextLevel) to the next level."
        )
    }

    private func progressLine(_ momentum: MomentumEngine.Snapshot) -> String {
        let toNext = "\(momentum.pointsToNextLevel) to level \(momentum.level + 1)"
        return momentum.todayEarned > 0 ? "+\(momentum.todayEarned) today · \(toNext)" : toNext
    }
}
