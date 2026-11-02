import SwiftUI

/// Thin trend line used on each `BiomarkerTile`. Just the
/// shape — no axis, no labels, no legend. Detail lives one tap
/// down in `BiomarkerDetailSheet`; on the card, the
/// sparkline's job is to answer "is the line going up or down"
/// in 200ms of glance time.
///
/// Path-based so it scales cleanly across the row's available
/// width and respects Dynamic Type without redrawing a chart
/// library at every accessibility size.
struct BiomarkerSparkline: View {
    /// Dated readings, oldest first. Plotted by date, so a week without
    /// readings shows as a week, not one step.
    let samples: [BiomarkerSnapshot.Sample]
    let tint: Color
    var height: CGFloat = 24

    /// The line is ink and the colour is kept for the latest reading
    /// only: a tinted line plus a tinted fill is two washes of colour
    /// competing with the number above it.
    private var lineColor: Color { AppColor.textPrimary.opacity(0.85) }

    var body: some View {
        GeometryReader { geo in
            let normalized = normalizedPoints(in: geo.size)
            ZStack {
                // The period's mean, so a glance answers "above or below
                // my normal?" and not just "up or down".
                if let meanY = meanY(in: geo.size) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: meanY))
                        path.addLine(to: CGPoint(x: geo.size.width, y: meanY))
                    }
                    .stroke(AppColor.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                }

                strokePath(points: normalized)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                // Tail dot — anchors the eye on the most recent
                // sample. Matches Bevel's "the line ends here"
                // affordance.
                if let last = normalized.last {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 10, height: 10)
                        .overlay { Circle().fill(tint).frame(width: 5, height: 5) }
                        .position(x: last.x, y: last.y)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)  // value + trend are on the row's text
    }

    /// Normalises the samples into the rendering rect: x by date
    /// between the first and last reading, y flipped because SwiftUI's
    /// coordinate space grows downward and higher values should render
    /// higher.
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return [] }
        let values = samples.map(\.value)
        let minValue = values.min() ?? 0
        let range = (values.max() ?? 1) - minValue
        let span = last.date.timeIntervalSince(first.date)
        return samples.map { sample in
            let x = span > 0 ? CGFloat(sample.date.timeIntervalSince(first.date) / span) * size.width : 0
            // When every sample is identical (flat HRV at 50 ms for 14
            // days) the range collapses to 0. Render the line through
            // the vertical middle instead of jamming it to the floor —
            // a flat-mid line reads as "steady," a flat-bottom line
            // read as "your HRV is at zero" (audit Biology follow-up).
            guard range > 0 else { return CGPoint(x: x, y: size.height / 2) }
            let normalized = (sample.value - minValue) / range
            return CGPoint(x: x, y: size.height - CGFloat(normalized) * size.height)
        }
    }

    private func meanY(in size: CGSize) -> CGFloat? {
        let values = samples.map(\.value)
        guard values.count >= 2, let minValue = values.min(), let maxValue = values.max(), maxValue > minValue else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return size.height - CGFloat((mean - minValue) / (maxValue - minValue)) * size.height
    }

    private func strokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            BiomarkerSparkline(
                samples: previewSamples([70.0, 70.2, 70.3, 70.5, 71.0, 71.5, 71.8, 72.0]),
                tint: AppColor.macroProtein
            )
            .frame(width: 80)
            BiomarkerSparkline(
                samples: previewSamples([58, 56, 54, 53, 51, 53, 50, 49, 51, 50]),
                tint: AppColor.metricHRV
            )
            .frame(width: 80)
        }
    }
    .preferredColorScheme(.dark)
}

private func previewSamples(_ values: [Double]) -> [BiomarkerSnapshot.Sample] {
    values.enumerated().map { index, value in
        BiomarkerSnapshot.Sample(
            date: Calendar.current.date(byAdding: .day, value: index - values.count, to: .now) ?? .now,
            value: value
        )
    }
}
