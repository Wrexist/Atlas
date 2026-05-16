import SwiftUI

/// Drifting point cloud rendered where the Bio Age number would
/// sit on the unlocked dial. Used as the locked-state visual —
/// Bevel's pattern: show what's there, blurred and beautiful, not
/// "🚫 denied". A user paying for Pro is buying the unblur, not
/// admission.
///
/// Particles drift via TimelineView so the canvas redraws at ~30
/// fps without forcing the whole view tree to re-evaluate.
/// Suppressed (rendered static) under Reduce Motion — the cluster
/// still implies "something rich is hidden here" without the
/// drift animation.
///
/// Deterministic seed so a given install always sees the same
/// arrangement — no shimmer between body re-evaluations.
struct BioAgeParticleCluster: View {
    var size: CGFloat = 200
    var particleCount: Int = 80
    var seed: UInt64 = 0x1E89_3B6C_F740_AA5C
    var tint: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? .infinity : 1.0 / 30)) { context in
            Canvas { ctx, canvasSize in
                drawParticles(
                    context: ctx,
                    canvasSize: canvasSize,
                    time: context.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .frame(width: size, height: size)
        .blur(radius: 1.6)
        .accessibilityHidden(true)
    }

    private func drawParticles(
        context: GraphicsContext,
        canvasSize: CGSize,
        time: TimeInterval
    ) {
        var generator = SplitMix64(seed: seed)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        // Elliptical bound: width slightly larger than height so
        // the cluster reads horizontal — matches the dial's
        // landscape proportion.
        let bound = CGSize(
            width:  canvasSize.width * 0.42,
            height: canvasSize.height * 0.28
        )

        for _ in 0..<particleCount {
            // Each particle gets a deterministic anchor inside
            // the elliptical bound + a phase offset for its drift.
            let r = Double.random(in: 0...1, using: &generator).squareRoot()
            let theta = Double.random(in: 0...(2 * .pi), using: &generator)
            let anchorX = center.x + CGFloat(r * cos(theta)) * bound.width
            let anchorY = center.y + CGFloat(r * sin(theta)) * bound.height

            let phaseOffset = Double.random(in: 0...(2 * .pi), using: &generator)
            let driftScale = Double.random(in: 0.4...1.4, using: &generator)
            // Slow drift — 3.5s period for a calm "the cluster
            // is alive" feel, not a tight twinkle.
            let phase = time * 1.8 + phaseOffset
            let dx = sin(phase) * 2.4 * driftScale
            let dy = cos(phase * 0.9) * 1.6 * driftScale

            let baseRadius = Double.random(in: 0.8...2.4, using: &generator)
            let baseOpacity = Double.random(in: 0.35...0.85, using: &generator)
            // Opacity also breathes so the cluster doesn't feel
            // mechanical. Half-amplitude so even at the trough
            // every particle is visible.
            let opacity = baseOpacity * (0.7 + 0.3 * sin(phase * 0.6))

            let x = anchorX + CGFloat(dx)
            let y = anchorY + CGFloat(dy)
            let rect = CGRect(
                x: x - CGFloat(baseRadius),
                y: y - CGFloat(baseRadius),
                width: baseRadius * 2,
                height: baseRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
        }
    }
}

#Preview {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeParticleCluster()
    }
    .preferredColorScheme(.dark)
}
