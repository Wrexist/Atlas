import SwiftUI

struct AchievementToastView: View {
    let achievement: Achievement
    @Binding var isShowing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isShowing {
            VStack {
                HStack(spacing: Spacing.md) {
                    MilestoneArtwork(symbol: achievement.icon, tint: AppColor.achievement, size: 48)
                        .id(achievement.id)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Achievement Unlocked!")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentLight)
                        Text(achievement.title)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                    }

                    Spacer()

                    Button {
                        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { isShowing = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: Spacing.minimumHitTarget,
                                   height: Spacing.minimumHitTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss")
                }
                .padding(Spacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.95))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Achievement unlocked: \(achievement.title)")
                .accessibilityValue(achievement.description)
                .accessibilityAddTraits(.isStaticText)

                Spacer()
            }
            .padding(.top, Spacing.sm)
            .task(id: achievement.id) {
                // A canceled toast must not dismiss the next queued achievement.
                do {
                    try await Task.sleep(for: .milliseconds(120))
                    Haptics.success()
                    try await Task.sleep(for: .seconds(4))
                    withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) {
                        isShowing = false
                    }
                } catch {
                    return
                }
            }
        }
    }
}
