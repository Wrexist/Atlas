import SwiftUI

/// Profile-screen card that surfaces the four most-recently-unlocked
/// achievements, with an "ellipsis +N" tile when there are more than
/// four. Reads the shared `AchievementService` singleton directly so
/// callers don't have to thread the achievement list through.
///
/// Split out of the parent `ProfileCustomizationSheet` — the badge
/// rendering and the empty-state copy are self-contained, with no
/// dependency on the sheet's many @State fields.
struct AchievementsPreviewCard: View {
    @State private var service = AchievementService.shared

    var body: some View {
        let unlocked = service.achievements
            .filter(\.isUnlocked)
            .sorted { ($0.unlockedDate ?? .distantPast) > ($1.unlockedDate ?? .distantPast) }

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Achievements", systemImage: "rosette")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(service.unlockedCount)/\(service.totalCount)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }

                if unlocked.isEmpty {
                    Text("Log doses, build streaks, and create protocols to start unlocking badges.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: Spacing.md) {
                        ForEach(unlocked.prefix(4)) { achievement in
                            badge(achievement)
                        }
                        if unlocked.count > 4 {
                            overflowTile(extra: unlocked.count - 4)
                        }
                    }
                }
            }
        }
    }

    private func badge(_ achievement: Achievement) -> some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .overlay {
                        Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                    }
                Image(systemName: achievement.icon)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(AppColor.accentLight)
            }
            .frame(width: 44, height: 44)

            Text(achievement.title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Achievement unlocked: \(achievement.title)")
        .accessibilityHint(achievement.description)
    }

    private func overflowTile(extra: Int) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppColor.textTertiary)
            Text("+\(extra)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
