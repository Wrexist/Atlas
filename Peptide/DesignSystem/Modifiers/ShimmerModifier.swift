import SwiftUI

/// Diagonal gradient sweep that animates across the view at a
/// steady cadence — the universal "this is loading, sit tight"
/// signal Apple uses in Health, Photos, and the App Store. Applied
/// via `.shimmer()` so any placeholder rectangle picks it up
/// without wiring its own animation.
///
/// Respects `accessibilityReduceMotion`: when the user has Reduce
/// Motion turned on the modifier stays a no-op, the placeholder
/// rendering as a flat tinted rectangle so we don't trigger
/// vestibular discomfort just to signal a loading state.
struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var sweeping = false

    /// The sweep has to move *away* from the surface it crosses: a lighter
    /// band on a dark skeleton, a darker one on a light skeleton. Pairing
    /// the tint with its matching blend mode keeps the effect visible in
    /// both schemes — `plusLighter` with a dark tint would be a no-op.
    private var sheen: Color { colorScheme == .dark ? .white : .black }
    private var blend: BlendMode { colorScheme == .dark ? .plusLighter : .multiply }

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: sheen.opacity(0.0),  location: 0.0),
                                .init(color: sheen.opacity(0.18), location: 0.45),
                                .init(color: sheen.opacity(0.28), location: 0.5),
                                .init(color: sheen.opacity(0.18), location: 0.55),
                                .init(color: sheen.opacity(0.0),  location: 1.0),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .rotationEffect(.degrees(20))
                        // Track the sweep across the row width
                        // plus a row-width pad either side so the
                        // gradient fully exits before looping back.
                        .offset(x: (sweeping ? 1 : -1) * width * 1.6)
                        .blendMode(blend)
                        .allowsHitTesting(false)
                    }
                    .mask(content)
                }
            }
            .motionAwareLoop(AppAnimation.loadingSweep, autoreverses: false, isRunning: $sweeping)
    }
}

extension View {
    /// Apply a 1.4s diagonal shimmer sweep over `self`. Use on
    /// skeleton placeholders — flat tinted rectangles read as
    /// "intentionally empty"; the shimmer reads as "loading
    /// real data".
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
