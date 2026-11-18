import SwiftUI

/// The top banner for an achievement unlock: a compact capsule that sits
/// under the status bar rather than a card over the navigation title.
/// `count` above one turns it into a summary of that many unlocks, shown
/// with the first one's artwork.
struct AchievementToastView: View {
    let achievement: Achievement
    var count = 1
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
        .padding(.top, Spacing.xs)
        .task(id: ToastKey(id: achievement.id, isShowing: isShowing)) {
            guard isShowing else { return }
            // A canceled toast must not dismiss the next queued achievement.
            do {
                try await Task.sleep(for: .milliseconds(120))
                Haptics.success()
                AccessibilityNotification.Announcement(announcement).post()
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

    private var isSummary: Bool { count > 1 }

    private var title: String {
        isSummary ? String(localized: "\(count) achievements unlocked") : achievement.title
    }

    private var announcement: String {
        isSummary ? title : String(localized: "Achievement unlocked: \(achievement.title)")
    }

    private var card: some View {
        HStack(spacing: Spacing.sm) {
            // Combined on its own so the Dismiss button stays a
            // separate, actionable VoiceOver element.
            HStack(spacing: Spacing.sm) {
                MilestoneArtwork(symbol: achievement.icon, tint: AppColor.achievement, size: 32)
                    .id(achievement.id)

                VStack(alignment: .leading, spacing: 0) {
                    if !isSummary {
                        Text("Achievement unlocked")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(title)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(announcement)
            .accessibilityValue(isSummary ? "" : achievement.description)
            .accessibilityAddTraits(.isStaticText)

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
        .padding(.leading, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        // A capsule hugging its content and inset well inside the
        // screen edges, so the large title and the trailing toolbar
        // button stay readable while it's up.
        .glassSurfaceCapsule()
        .padding(.horizontal, Spacing.xxxxl)
        // A transient banner, capped like the system's: at the largest
        // sizes it would otherwise cover half the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
