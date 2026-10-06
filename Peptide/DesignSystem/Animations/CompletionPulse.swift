import SwiftUI

/// Local acknowledgment for a completed action. Animates only the glyph,
/// leaving the control's layout and hit target stationary. No arrival loop.
private struct CompletionPulse: ViewModifier {
    let trigger: Int
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private struct Pose {
        var scale: CGFloat = 1
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Pose(), trigger: trigger) { view, pose in
            view.scaleEffect(isActive && !reduceMotion && scenePhase == .active ? pose.scale : 1)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.15, duration: 0.12)
                CubicKeyframe(1, duration: 0.24)
            }
        }
    }
}

extension View {
    func completionPulse(trigger: Int, isActive: Bool = true) -> some View {
        modifier(CompletionPulse(trigger: trigger, isActive: isActive))
    }
}
