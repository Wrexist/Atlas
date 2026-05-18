import SwiftUI

/// Tiny inline trend line used on each `BiomarkerRow`. Just the
/// shape — no axis, no labels, no legend. Detail lives one tap
/// down in `BiomarkerDetailSheet` (commit 8); on the row, the
/// sparkline's job is to answer "is the line going up or down"
/// in 200ms of glance time.
///
/// Path-based so it scales cleanly across the row's available
/// width and respects Dynamic Type without redrawing a chart
/// library at every accessibility size.
struct BiomarkerSparkline: View {
    let points: [Double]
    let tint: Color
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let normalized = normalizedPoints(in: geo.size)
            ZStack {
                // Gradient fill under the stroke for depth. Hidden
                // when fewer than two points — the fill would
                // render as a triangle, not a sparkline shape.
                if normalized.count >= 2 {
                    fillPath(points: normalized, size: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.35), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                strokePath(points: normalized)
                    .stroke(
                        tint.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                // Tail dot — anchors the eye on the most recent
                // sample. Matches Bevel's "the line ends here"
                // affordance.
                if let last = normalized.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 4, height: 4)
                        .position(x: last.x, y: last.y)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)  // value + trend are on the row's text
    }

    /// Normalises raw values into the rendering rect. y-axis
    /// flipped because SwiftUI's coordinate space has y growing
    /// downward; we want higher values to render higher on the
    /// chart.
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        let minValue = points.min() ?? 0
        let maxValue = points.max() ?? 1
        let range = maxValue - minValue
        let stepX = size.width / CGFloat(points.count - 1)
        // When every sample is identical (flat HRV at 50 ms for 14
        // days) the range collapses to 0. Render the line through
        // the vertical middle instead of jamming it to the floor —
        // a flat-mid line reads as "steady," a flat-bottom line
        // read as "your HRV is at zero" (audit Biology follow-up).
        guard range > 0 else {
            let midY = size.height / 2
            return points.enumerated().map { idx, _ in
                CGPoint(x: CGFloat(idx) * stepX, y: midY)
            }
        }
        return points.enumerated().map { idx, value in
            let x = CGFloat(idx) * stepX
            let normalized = (value - minValue) / range
            let y = size.height - (CGFloat(normalized) * size.height)
            return CGPoint(x: x, y: y)
        }
    }

    private func strokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// Stroke path closed along the bottom so the gradient fill
    /// reads as a soft tinted area below the line, not a random
    /// polygon.
    private func fillPath(points: [CGPoint], size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            BiomarkerSparkline(
                points: [70.0, 70.2, 70.3, 70.5, 71.0, 71.5, 71.8, 72.0],
                tint: AppColor.macroProtein
            )
            .frame(width: 80)
            BiomarkerSparkline(
                points: [58, 56, 54, 53, 51, 53, 50, 49, 51, 50],
                tint: AppColor.metricHRV
            )
            .frame(width: 80)
        }
    }
    .preferredColorScheme(.dark)
}
