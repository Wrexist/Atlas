import SwiftUI

struct AchievementToastView: View {
    let achievement: Achievement
    @Binding var isShowing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        // The VStack stays mounted and only the card comes and goes, so a
        // removal always slides out from the top. With the whole stack
        // inside the `if`, an outgoing card lost its Spacer and was left
        // centred on screen while the next unlock slid in above it.
        VStack {
            if isShowing {
                card
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, Spacing.sm)
        .task(id: ToastKey(id: achievement.id, isShowing: isShowing)) {
            guard isShowing else { return }
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

    private struct ToastKey: Equatable {
        let id: String
        let isShowing: Bool
    }

    private var card: some View {
        HStack(spacing: Spacing.md) {
            // Combined on its own so the Dismiss button stays a
            // separate, actionable VoiceOver element.
            HStack(spacing: Spacing.md) {
                MilestoneArtwork(symbol: achievement.icon, tint: AppColor.achievement, size: 48)
                    .id(achievement.id)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Achievement unlocked")
                        .font(AppFont.caption2)
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
        // Same surface as SyncToast, so the two top toasts read as
        // one family.
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .padding(.horizontal, Spacing.screenPadding)
    }
}
