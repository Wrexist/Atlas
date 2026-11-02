import SwiftUI

/// Cards below the fold ease in as they scroll into view and settle back
/// as they leave, tied to the scroll position rather than a timer. Unlike
/// `sectionAppear`, nothing plays off-screen. Under Reduce Motion the
/// card only fades.
private struct ScrollReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moves = !reduceMotion
        return content.scrollTransition { card, phase in
            card
                .opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(moves && !phase.isIdentity ? 0.98 : 1)
                .offset(y: moves ? phase.value * 12 : 0)
        }
    }
}

/// A large title that hands off to a sticky bar: it fades and shrinks
/// toward its leading edge as it scrolls under the top.
private struct ScrollHandOff: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moves = !reduceMotion
        return content.scrollTransition(axis: .vertical) { header, phase in
            header
                .opacity(phase == .topLeading ? 0 : 1)
                .scaleEffect(moves && phase == .topLeading ? 0.94 : 1, anchor: .topLeading)
                .blur(radius: moves && phase == .topLeading ? 4 : 0)
        }
    }
}

extension View {
    func scrollReveal() -> some View {
        modifier(ScrollReveal())
    }

    func scrollHandOff() -> some View {
        modifier(ScrollHandOff())
    }
}
