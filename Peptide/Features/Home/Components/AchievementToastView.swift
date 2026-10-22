import SwiftUI

struct AchievementToastView: View {
    let achievement: Achievement
    @Binding var isShowing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        if isShowing {
            VStack {
                HStack(spacing: Spacing.md) {
                    // Combined on its own so the Dismiss button stays a
                    // separate, actionable VoiceOver element.
                    HStack(spacing: Spacing.md) {
                        MilestoneArtwork(symbol: achievement.icon, tint: AppColor.achievement, size: 48)
                            .id(achievement.id)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Achievement unlocked")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.accentLight)
                            Text(achievement.title)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Achievement unlocked: \(achievement.title)")
                    .accessibilityValue(achievement.description)
                    .accessibilityAddTraits(.isStaticText)

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
                // Same glass as SyncToast, so the two top toasts read as
                // one family.
                .glassSurface(cornerRadius: Spacing.cardCornerRadius)
                .padding(.horizontal, Spacing.screenPadding)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))

                Spacer()
            }
            .padding(.top, Spacing.sm)
            .task(id: achievement.id) {
                // A canceled toast must not dismiss the next queued achievement.
                do {
                    try await Task.sleep(for: .milliseconds(120))
                    Haptics.success()
                    AccessibilityNotification.Announcement(
                        String(localized: "Achievement unlocked: \(achievement.title)")
                    ).post()
                    // VoiceOver needs time to finish the announcement and
                    // reach the Dismiss button before the toast hides.
                    try await Task.sleep(for: .seconds(voiceOverEnabled ? 10 : 4))
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
