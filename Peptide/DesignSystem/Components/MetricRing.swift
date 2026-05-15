import SwiftUI

/// Configurable ring used across the Today hero trio, calorie panels,
/// and protocol-score surfaces. One source of truth so the visual
/// language stays consistent — a tweak to stroke width or animation
/// curve takes effect everywhere a metric ring lives.
///
/// Renders a track + gradient progress arc + an optional centred
/// content view (usually a big percentage label). `progress` is
/// clamped 0…1 so the arc never wraps and out-of-bounds inputs (e.g.
/// `score > 1.0` from a stale value) degrade cleanly.
struct MetricRing<Center: View>: View {
    let progress: Double
    let diameter: CGFloat
    let strokeWidth: CGFloat
    let gradient: [Color]
    /// When set, a hatched "capacity used" band replaces the leading
    /// portion of the track. Mirrors Bevel's Strain ring where the
    /// striped section indicates "already spent today". Pass `nil` to
    /// disable.
    let hatchedFraction: Double?
    @ViewBuilder let center: () -> Center

    init(
        progress: Double,
        diameter: CGFloat = 100,
        strokeWidth: CGFloat = 11,
        gradient: [Color],
        hatchedFraction: Double? = nil,
        @ViewBuilder center: @escaping () -> Center
    ) {
        self.progress = max(0, min(1, progress))
        self.diameter = diameter
        self.strokeWidth = strokeWidth
        self.gradient = gradient
        self.hatchedFraction = hatchedFraction.map { max(0, min(1, $0)) }
        self.center = center
    }

    var body: some View {
        ZStack {
            // Track — the unfilled portion of the ring. Slightly
            // brighter than pure black so the progress arc reads even
            // at low values.
            Circle()
                .stroke(AppColor.surfaceElevated.opacity(0.7), lineWidth: strokeWidth)

            // Hatched capacity band (optional). Drawn on top of the
            // track but underneath the progress arc.
            if let hatched = hatchedFraction, hatched > 0 {
                hatchedArc(fraction: hatched)
            }

            // Progress arc.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradient),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            center()
        }
        .frame(width: diameter, height: diameter)
    }

    /// Drawn as a striped pattern over the same trim arc so it reads
    /// as part of the ring, not a separate overlay. Uses a fixed
    /// 4pt-on / 3pt-off dash so the stripes stay legible at every
    /// size.
    private func hatchedArc(fraction: Double) -> some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(
                gradient.first?.opacity(0.45) ?? Color.white.opacity(0.3),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt, dash: [4, 3])
            )
            .rotationEffect(.degrees(-90))
    }
}

// MARK: - Empty-center convenience

extension MetricRing where Center == EmptyView {
    init(
        progress: Double,
        diameter: CGFloat = 100,
        strokeWidth: CGFloat = 11,
        gradient: [Color],
        hatchedFraction: Double? = nil
    ) {
        self.init(
            progress: progress,
            diameter: diameter,
            strokeWidth: strokeWidth,
            gradient: gradient,
            hatchedFraction: hatchedFraction,
            center: { EmptyView() }
        )
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HStack(spacing: Spacing.lg) {
            MetricRing(
                progress: 0.17,
                gradient: [Color.orange, Color.yellow],
                hatchedFraction: 0.30
            ) {
                Text("17%")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            MetricRing(
                progress: 0.85,
                gradient: [Color.green, Color(red: 0.72, green: 0.96, blue: 0.34)]
            ) {
                Text("85%")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            MetricRing(
                progress: 0.82,
                gradient: [Color.purple, Color(red: 0.66, green: 0.62, blue: 0.96)]
            ) {
                Text("82%")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
    .preferredColorScheme(.dark)
}
