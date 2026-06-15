import SwiftUI

/// Lightweight confetti burst built on `Canvas` + `TimelineView` — no
/// SpriteKit dependency, no view-per-particle overhead. Shards radiate
/// from `origin`, arc upward, then fall under gravity and fade over
/// `duration`. Purely decorative: hit-testing off, hidden from
/// VoiceOver. The host mounts it for the burst's lifetime and removes
/// it when done; Reduce Motion is honored by the host (which simply
/// doesn't mount it).
struct ConfettiView: View {
    var colors: [Color]
    var intensity: Int = 60
    var origin: UnitPoint = .center
    var duration: TimeInterval = 1.8

    @State private var particles: [Particle] = []
    @State private var start = Date()

    private struct Particle: Identifiable {
        let id: Int
        let vx: Double      // normalized horizontal velocity (fraction of width / s)
        let vy: Double      // normalized vertical velocity (fraction of height / s)
        let color: Color
        let size: Double    // points
        let spin: Double    // radians / s
        let aspect: Double  // height-to-width ratio so shards aren't all square
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed <= duration else { return }

                // Keep the kinematics in Double, convert to CGFloat only at
                // the GraphicsContext boundary, to avoid Double/CGFloat
                // inference ambiguity.
                let width = Double(size.width)
                let height = Double(size.height)
                let gravity = 1.1
                let originX = Double(origin.x) * width
                let originY = Double(origin.y) * height
                let fade = max(0, 1 - elapsed / duration)

                for particle in particles {
                    let x = originX + particle.vx * elapsed * width
                    let y = originY + (particle.vy * elapsed + 0.5 * gravity * elapsed * elapsed) * height

                    var shardContext = context
                    shardContext.opacity = fade
                    shardContext.translateBy(x: CGFloat(x), y: CGFloat(y))
                    shardContext.rotate(by: .radians(particle.spin * elapsed))

                    let rect = CGRect(
                        x: -particle.size / 2,
                        y: -(particle.size * particle.aspect) / 2,
                        width: particle.size,
                        height: particle.size * particle.aspect
                    )
                    shardContext.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(particle.color)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear(perform: generate)
    }

    private func generate() {
        start = Date()
        let palette = colors.isEmpty ? [AppColor.accentPrimary] : colors
        particles = (0..<max(1, intensity)).map { index in
            // Radial spread, biased upward so the shards arc out and then
            // rain back down rather than just dropping straight.
            let angle = Double.random(in: 0..<(2 * .pi))
            let speed = Double.random(in: 0.25...0.95)
            return Particle(
                id: index,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed - Double.random(in: 0.4...0.9),
                color: palette[index % palette.count],
                size: Double.random(in: 6...11),
                spin: Double.random(in: -6...6),
                aspect: Double.random(in: 0.45...1.0)
            )
        }
    }
}
