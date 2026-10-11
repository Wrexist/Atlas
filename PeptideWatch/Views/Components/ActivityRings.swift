import SwiftUI

/// One ring of `ActivityRings`: progress 0…1 in a single colour.
struct RingSpec: Identifiable {
    let id: String
    let progress: Double
    let color: Color
}

/// Concentric progress rings, outermost first, in the shape of the
/// Activity app's Move / Exercise / Stand stack. Each fill darkens
/// toward its start so the leading edge reads as "how far you got".
struct ActivityRings: View {
    let rings: [RingSpec]
    var lineWidth: CGFloat = 14
    var spacing: CGFloat = 2

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                ProgressRing(progress: ring.progress, color: ring.color, lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + spacing))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ProgressRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.7), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(clamped, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: clamped)
        }
        .padding(lineWidth / 2)
    }
}
