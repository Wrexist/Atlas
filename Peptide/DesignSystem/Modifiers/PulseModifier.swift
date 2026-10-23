import SwiftUI

/// Slow opacity breathe for "this is live" affordances. Honours Reduce
/// Motion: a loop that never stops is the motion type WCAG 2.2.2 is about,
/// so with it on the content simply renders at full opacity.
struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.6 : 1.0)
            .motionAwareLoop(AppAnimation.breathe, autoreverses: true, isRunning: $pulsing)
    }
}

extension View {
    func pulse() -> some View {
        modifier(PulseModifier())
    }
}
