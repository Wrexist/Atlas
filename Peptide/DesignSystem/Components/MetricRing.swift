import SwiftUI

/// Configurable ring used across the Today hero trio, the protocol
/// score card, the stack-completeness tile, and (eventually) every
/// other ring surface. One source of truth so the visual language
/// stays consistent — a tweak to stroke width or animation curve
/// takes effect everywhere a metric ring lives.
///
/// Renders a track + gradient progress arc + an optional centred
/// content view. `progress` is clamped 0…1 so the arc never wraps
/// and out-of-bounds inputs (e.g. `score > 1.0` from a stale
/// value, or NaN from a 0/0 ratio) degrade cleanly.
///
/// No accent halo under the arc: Craft R2 — emphasis comes from size,
/// weight, contrast and space, never from a coloured glow.
///
/// Three optional behaviours stay defaulted-off so callers like
/// `HeroMetricTrio` opt into the simple ring, while branded
/// surfaces like the adherence detail sheet opt in to the appear sweep +
/// celebration pulse. `GlassProgressBar` is the linear
/// counterpart for the same idea inside a row.
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
    /// Sweeps the arc from 0 → `progress` once on appear via spring.
    /// Defaults off — the hero trio mounts with its values ready and
    /// doesn't want a flash. The protocol-score card uses it to draw
    /// the eye to the day's adherence.
    let appearAnimated: Bool
    /// When `progress` crosses 1.0 from below, briefly scale-pulses
    /// the centre content so a finished day reads as a moment, not
    /// just a number flip. Suppressed under Reduce Motion.
    let celebrateAtCompletion: Bool
    /// Content centred inside the ring, typically the value and its label.
    @ViewBuilder let center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0
    @State private var hasAppeared = false
    @State private var completionTrigger = 0

    init(
        progress: Double,
        diameter: CGFloat = 100,
        strokeWidth: CGFloat = 11,
        gradient: [Color],
        hatchedFraction: Double? = nil,
        appearAnimated: Bool = false,
        celebrateAtCompletion: Bool = false,
        @ViewBuilder center: @escaping () -> Center
    ) {
        self.progress = progress.unitClamped
        self.diameter = diameter
        self.strokeWidth = strokeWidth
        self.gradient = gradient
        self.hatchedFraction = hatchedFraction.map(\.unitClamped)
        self.appearAnimated = appearAnimated
        self.celebrateAtCompletion = celebrateAtCompletion
        self.center = center
    }

    var body: some View {
        ZStack {
            // Track — the unfilled portion of the ring, so a low value
            // still reads as part of a whole in both schemes.
            Circle()
                .stroke(AppColor.track, lineWidth: strokeWidth)

            // Hatched capacity band (optional). Drawn on top of the
            // track but underneath the progress arc.
            if let hatched = hatchedFraction, hatched > 0 {
                hatchedArc(fraction: hatched)
            }

            // Progress arc.
            progressArc

            // Centres hold a short number, and `AppFont.scaled` has no
            // cap, so at accessibility sizes they shrink to fit inside the
            // stroke instead of spilling over it.
            center()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: centerSide, maxHeight: centerSide)
                .completionPulse(trigger: completionTrigger, isActive: celebrateAtCompletion && progress >= 1)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { handleAppear() }
        .onChange(of: progress) { oldValue, newValue in
            handleProgressChange(from: oldValue, to: newValue)
        }
    }

    /// The square that fits inside the ring's inner edge.
    private var centerSide: CGFloat {
        max(0, (diameter - 2 * strokeWidth) * 0.75)
    }

    @ViewBuilder
    private var progressArc: some View {
        let renderedProgress = appearAnimated && !reduceMotion ? animatedProgress : progress
        let arc = Circle()
            .trim(from: 0, to: renderedProgress)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: arcColors(closed: renderedProgress >= 1)),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: renderedProgress)

        arc
    }

    /// A full ring's end cap lands on its start, so an open gradient shows
    /// a hard colour step at 12 o'clock and 100% reads like an arc that
    /// almost made it. Closing the gradient back to its first stop draws
    /// a seamless loop exactly when the goal is met.
    private func arcColors(closed: Bool) -> [Color] {
        guard closed, let first = gradient.first, gradient.count > 1 else { return gradient }
        return gradient + [first]
    }

    /// Drawn as a striped pattern over the same trim arc so it reads
    /// as part of the ring, not a separate overlay. Uses a fixed
    /// 4pt-on / 3pt-off dash so the stripes stay legible at every
    /// size.
    private func hatchedArc(fraction: Double) -> some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(
                gradient.first?.opacity(0.45) ?? AppColor.textPrimary.opacity(0.3),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt, dash: [4, 3])
            )
            .rotationEffect(.degrees(-90))
    }

    // MARK: - Animation hooks
    //
    // Wired only when the caller opts in via `appearAnimated` /
    // `celebrateAtCompletion`. For the simple ring path (the hero
    // trio), `animatedProgress` is set once on appear and never
    // touched again — the body reads from `progress` directly.

    private func handleAppear() {
        guard appearAnimated else {
            animatedProgress = progress
            hasAppeared = true
            return
        }
        if hasAppeared {
            animatedProgress = progress
        } else {
            hasAppeared = true
            withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) {
                animatedProgress = progress
            }
        }
    }

    private func handleProgressChange(from old: Double, to new: Double) {
        if appearAnimated {
            withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) {
                animatedProgress = new
            }
        }
        if celebrateAtCompletion, old < 1.0, new >= 1.0, !reduceMotion {
            completionTrigger &+= 1
        }
    }
}

// MARK: - Progress clamping

extension Double {
    /// Clamped to 0…1 for ring and bar fills, with NaN and infinities
    /// mapped to 0. `min(1, .nan)` returns 1, so a plain clamp would draw
    /// a 0/0 ratio as a full ring.
    var unitClamped: Double {
        isFinite ? Swift.min(Swift.max(self, 0), 1) : 0
    }
}

// MARK: - Empty-center convenience

extension MetricRing where Center == EmptyView {
    init(
        progress: Double,
        diameter: CGFloat = 100,
        strokeWidth: CGFloat = 11,
        gradient: [Color],
        hatchedFraction: Double? = nil,
        appearAnimated: Bool = false,
        celebrateAtCompletion: Bool = false
    ) {
        self.init(
            progress: progress,
            diameter: diameter,
            strokeWidth: strokeWidth,
            gradient: gradient,
            hatchedFraction: hatchedFraction,
            appearAnimated: appearAnimated,
            celebrateAtCompletion: celebrateAtCompletion,
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
                    .font(AppFont.scaled(20, weight: .medium))
                    .foregroundStyle(.white)
            }
            MetricRing(
                progress: 0.85,
                gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                appearAnimated: true,
                celebrateAtCompletion: true
            ) {
                Text("85")
                    .font(AppFont.scaled(30, weight: .light, in: .large))
                    .foregroundStyle(.white)
            }
        }
    }
    .preferredColorScheme(.dark)
}
