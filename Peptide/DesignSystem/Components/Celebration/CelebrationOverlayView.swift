import SwiftUI

/// A dimensional tier medal and the real level the user reached.
/// Presentational only — the host controls how long it stays
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

    var body: some View {
        VStack(spacing: Spacing.md) {
            MilestoneArtwork(symbol: tierSymbol, tint: tint, size: 112)

            VStack(spacing: Spacing.xxs) {
                Text("LEVEL \(level)")
                    .font(AppFont.scaled(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                    .monospacedDigit()
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
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Level \(level) reached. \(tierName) tier.")
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(AppAnimation.springSmooth) { appeared = true }
            }
            // SwiftUI-native announcement so the moment isn't silent for
            // VoiceOver users (avoids importing UIKit just for this).
            AccessibilityNotification.Announcement("Level \(level) reached").post()
        }
    }
}
