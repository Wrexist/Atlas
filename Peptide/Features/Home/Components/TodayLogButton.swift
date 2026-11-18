import SwiftUI

/// Today's one quick-log control, beside the avatar in the greeting.
/// It replaced the jump bar's chip row: with fewer sections on Today
/// there's nothing left to jump to, and a strip of chips above the
/// first card was one more thing to read before anything useful.
struct TodayLogButton: View {
    /// Whether the parent's quick-log sheet is up. Turns the "+" into a
    /// "×" so the control reads as the thing that opened the sheet.
    let isOpen: Bool
    /// Whether the tap opens the meal-or-dose menu. Without a pending
    /// dose it goes straight to the meal scanner, and the hint says so.
    let includesDose: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            // Rotating "+" 45° draws the "×"; under Reduce Motion the
            // glyph swaps instead so nothing spins.
            // A filled, labelled pill so the day's one primary action
            // never reads as a second avatar next to the profile button.
            HStack(spacing: Spacing.xs) {
                Image(systemName: isOpen && reduceMotion ? "xmark" : "plus")
                    .rotationEffect(.degrees(isOpen && !reduceMotion ? 45 : 0))
                    .animation(
                        AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion),
                        value: isOpen
                    )
                Text("Log")
                    .fixedSize()
            }
            .font(AppFont.scaled(16, weight: .semibold))
            .foregroundStyle(AppColor.inverseInk)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background {
                Capsule().fill(LinearGradient(
                    colors: [AppColor.ctaGradientStart, AppColor.ctaGradientEnd],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.9, pressedOpacity: 0.85))
        .accessibilityLabel("Log")
        .accessibilityHint(includesDose
            ? Text("Opens a menu to snap a meal photo or log your next dose.")
            : Text("Opens the meal scanner."))
    }
}

#Preview {
    HStack(spacing: Spacing.md) {
        TodayLogButton(isOpen: false, includesDose: true, action: {})
        TodayLogButton(isOpen: true, includesDose: false, action: {})
    }
    .padding(Spacing.lg)
}
