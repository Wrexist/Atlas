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
    @State private var phase: CGFloat = -1.0

    /// One full sweep duration. 1.4s is the same beat Health.app
    /// + the App Store skeletons use — slow enough to read as
    /// "still working" without feeling like the loop is stalling.
    private let duration: Double = 1.4

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.0),  location: 0.0),
                                .init(color: .white.opacity(0.18), location: 0.45),
                                .init(color: .white.opacity(0.28), location: 0.5),
                                .init(color: .white.opacity(0.18), location: 0.55),
                                .init(color: .white.opacity(0.0),  location: 1.0),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .rotationEffect(.degrees(20))
                        // Track the sweep across the row width
                        // plus a row-width pad either side so the
                        // gradient fully exits before looping back.
                        .offset(x: phase * width * 1.6)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    }
                    .mask(content)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: duration).repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
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
