import SwiftUI

/// Centered "big moment" card for a level-up, reusing
/// `AchievementToastView`'s glass + `symbolEffect(.bounce)` visual
/// language. Presentational only — the host controls how long it stays
/// up and dismisses it. Honors Reduce Motion (opacity-only, no scale
/// pop) and posts a VoiceOver announcement so the moment isn't silent
/// for assistive-tech users.
struct CelebrationOverlayView: View {
    let level: Int
    let tierName: String
    let tierSymbol: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var iconBounce = 0

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Image(systemName: tierSymbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: iconBounce)
            }

            VStack(spacing: Spacing.xxs) {
                Text("LEVEL \(level)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
                Text("\(tierName) tier")
                    .font(AppFont.subheadline)
                    .foregroundStyle(tint)
                Text("Your consistency is paying off.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.xxl)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
                .appShadow(AppShadow.glassDeep)
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Level \(level) reached. \(tierName) tier.")
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
                iconBounce &+= 1
            }
            // SwiftUI-native announcement so the moment isn't silent for
            // VoiceOver users (avoids importing UIKit just for this).
            AccessibilityNotification.Announcement("Level \(level) reached").post()
        }
    }
}
