import SwiftUI

/// One ring of `ActivityRings`: progress 0…1 in a single colour, with the
/// SF Symbol that sits at its start the way Activity's arrows do.
struct RingSpec: Identifiable {
    let id: String
    let progress: Double
    let color: Color
    let symbol: String
}

/// Concentric progress rings, outermost first, in the shape of the
/// Activity app's Move / Exercise / Stand stack. The rings draw in from
/// zero, one after another, each time their page comes on screen.
struct ActivityRings: View {
    let rings: [RingSpec]
    var lineWidth: CGFloat = 14
    var spacing: CGFloat = 2

    @Environment(\.watchPageIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                ProgressRing(
                    progress: revealed ? ring.progress : 0,
                    color: ring.color,
                    symbol: ring.symbol,
                    lineWidth: lineWidth
                )
                .padding(CGFloat(index) * (lineWidth + spacing))
                .animation(
                    reduceMotion ? nil : WatchMotion.entrance.delay(Double(index) * WatchMotion.stagger),
                    value: revealed
                )
                .animation(WatchMotion.update, value: ring.progress)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { revealed = isActive || reduceMotion }
        .onChange(of: isActive) { revealed = isActive || reduceMotion }
    }
}

private struct ProgressRing: View {
    let progress: Double
    let color: Color
    let symbol: String
    let lineWidth: CGFloat

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            // A sliver of trim at zero still draws the round start cap, so
            // the symbol always sits on its own colour, as in Activity.
            Circle()
                .trim(from: 0, to: max(clamped, 0.0001))
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
        }
        .padding(lineWidth / 2)
        .overlay(alignment: .top) {
            Image(systemName: symbol)
                .font(.system(size: lineWidth * 0.6, weight: .heavy))
                .foregroundStyle(.black)
                .frame(height: lineWidth)
        }
    }
}
