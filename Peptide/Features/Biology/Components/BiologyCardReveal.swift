import SwiftUI

/// Biology's cards ease in as they scroll into view and settle back as
/// they leave, tied to scroll position rather than a timer, so nothing
/// plays off-screen. The threshold keeps a tall card at rest while most
/// of it is readable. Under Reduce Motion a card only fades.
private struct BiologyCardReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moves = !reduceMotion
        return content.scrollTransition(.interactive.threshold(.visible(0.3)), axis: .vertical) { card, phase in
            card
                .opacity(phase.isIdentity ? 1 : 0.4)
                .scaleEffect(moves && !phase.isIdentity ? 0.96 : 1)
                .offset(y: moves ? phase.value * 16 : 0)
        }
    }
}

extension View {
    func biologyCardReveal() -> some View {
        modifier(BiologyCardReveal())
    }
}
