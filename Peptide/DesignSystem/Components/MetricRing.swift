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
/// value) degrade cleanly.
///
/// Three optional behaviours stay defaulted-off so callers like
/// `HeroMetricTrio` opt into the simple ring, while branded
/// surfaces like `ProtocolScoreCard` opt in to the appear sweep +
/// celebration pulse + accent glow. `GlassProgressBar` is the linear
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
    /// Removed: this used to add an accent halo under the arc. Craft R2 —
    /// emphasis comes from size, weight, contrast and space, never from a
    /// coloured glow. The ring is already the largest thing on its card.
    /// rings use it; the hero trio doesn't (the trio sits on a glass
    @ViewBuilder let center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0
    @State private var hasAppeared = false
    @State private var celebrationScale: CGFloat = 1.0

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
        self.progress = max(0, min(1, progress))
        self.diameter = diameter
        self.strokeWidth = strokeWidth
        self.gradient = gradient
        self.hatchedFraction = hatchedFraction.map { max(0, min(1, $0)) }
        self.appearAnimated = appearAnimated
        self.celebrateAtCompletion = celebrateAtCompletion
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
            progressArc

            center()
                .scaleEffect(celebrationScale)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { handleAppear() }
        .onChange(of: progress) { oldValue, newValue in
            handleProgressChange(from: oldValue, to: newValue)
        }
    }

    @ViewBuilder
    private var progressArc: some View {
        let renderedProgress = appearAnimated ? animatedProgress : progress
        let arc = Circle()
            .trim(from: 0, to: renderedProgress)
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

        arc
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
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                animatedProgress = progress
            }
        }
    }

    private func handleProgressChange(from old: Double, to new: Double) {
        let clamped = max(0, min(1, new))
        if appearAnimated {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                animatedProgress = clamped
            }
        }
        if celebrateAtCompletion, old < 1.0, clamped >= 1.0, !reduceMotion {
            triggerCelebration()
        }
    }

    private func triggerCelebration() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            celebrationScale = 1.08
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                celebrationScale = 1.0
            }
        }
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
                    .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            MetricRing(
                progress: 0.85,
                gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                appearAnimated: true,
                celebrateAtCompletion: true
            ) {
                Text("85")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
    .preferredColorScheme(.dark)
}
