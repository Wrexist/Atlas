import SwiftUI

/// Slow opacity breathe for "this is live" affordances. Honours Reduce
/// Motion: a loop that never stops is the motion type WCAG 2.2.2 is about,
/// so with it on the content simply renders at full opacity.
struct PulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear {
                guard !reduceMotion else { return }
                pulsing = true
            }
    }
}

extension View {
    func pulse() -> some View {
        modifier(PulseModifier())
    }
}
