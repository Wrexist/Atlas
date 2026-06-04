import SwiftUI

/// Tier of highlight applied to a single muscle on `MuscleMapView`.
/// Used by the exercise-detail screen (primary + secondary tints to
/// match the Lyfta reference) and by the weekly heatmap (intensity
/// 0…1 from cool to hot).
enum MuscleHighlight: Hashable, Sendable {
    /// Fully-saturated primary tint — the muscle the exercise is
    /// built around.
    case primary
    /// Soft secondary tint — assisting muscles that get worked but
    /// aren't the focus.
    case secondary
    /// Frequency-driven shade for the weekly heatmap.
    /// `0.0` is dim, `1.0` is fully lit.
    case intensity(Double)
}

/// Anatomical figure that highlights a configurable set of muscles.
/// Three modes:
///
/// - **Exercise detail** — pass a `[muscle: .primary | .secondary]`
///   map. Renders the figure with primary muscles glowing in red and
///   secondary muscles in cool blue, matching the screenshots from
///   the Lyfta reference.
/// - **Weekly heatmap** — pass `[muscle: .intensity(0…1)]`. Renders
///   a single-colour gradient where well-trained muscles light up
///   warmer.
/// - **Empty** — pass `[:]` (or omit). Renders the silhouette as a
///   calm baseline so the surface still reads as the user's body
///   even before they've logged anything.
///
/// Render performance: a single `Canvas` draws the silhouette + every
/// muscle in one pass, so even when the highlights animate on
/// workout finish the view stays at 60fps on small phones.
struct MuscleMapView: View {

    let highlights: [AnatomicalMuscle: MuscleHighlight]
    var orientation: Orientation = .both
    var primaryColor: Color = Color(red: 0.93, green: 0.27, blue: 0.30)
    var secondaryColor: Color = Color(red: 0.42, green: 0.58, blue: 0.95)
    var heatmapHotColor: Color = Color(red: 0.95, green: 0.40, blue: 0.30)
    var silhouetteFill: Color = Color.white.opacity(0.06)
    var silhouetteStroke: Color = Color.white.opacity(0.18)
    /// Faint skeletal scaffold drawn under the muscles so the figure
    /// reads as an anatomy chart rather than a flat blob.
    var showsSkeleton: Bool = true
    var skeletonColor: Color = Color.white.opacity(0.14)

    enum Orientation {
        case front, back, both
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if orientation == .front || orientation == .both {
                    figure(facing: .front, in: proxy.size)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityLabel(for: .front))
                }
                if orientation == .back || orientation == .both {
                    figure(facing: .back, in: proxy.size)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityLabel(for: .back))
                }
            }
        }
        .aspectRatio(orientation == .both ? BodyAnatomy.aspect * 2 : BodyAnatomy.aspect,
                     contentMode: .fit)
    }

    // MARK: - Figure

    private enum Facing { case front, back }

    @ViewBuilder
    private func figure(facing: Facing, in containerSize: CGSize) -> some View {
        let muscles = facing == .front
            ? AnatomicalMuscle.allCases.filter { !$0.isBack }
            : AnatomicalMuscle.allCases.filter { $0.isBack }
        let silhouette = facing == .front
            ? BodyAnatomy.frontSilhouette()
            : BodyAnatomy.backSilhouette()

        Canvas(rendersAsynchronously: false) { context, size in
            let scale = transform(for: size)
            let body = silhouette.applying(scale)

            // Silhouette layer — a soft vertical gradient + thin stroke
            // gives the body a little depth so it reads even when no
            // muscle is highlighted.
            let bounds = body.boundingRect
            context.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [
                        silhouetteFill.opacity(1.5),
                        silhouetteFill.opacity(0.7),
                    ]),
                    startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                    endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
                )
            )
            context.stroke(
                body,
                with: .color(silhouetteStroke),
                style: StrokeStyle(lineWidth: 1, lineJoin: .round)
            )

            // Skeleton scaffold — clipped to the body so bones never
            // poke past the silhouette, drawn faint under the muscles.
            if showsSkeleton {
                var boneContext = context
                boneContext.clip(to: body)
                boneContext.stroke(
                    BodyAnatomy.skeleton(facing: facing == .front).applying(scale),
                    with: .color(skeletonColor),
                    style: StrokeStyle(lineWidth: 0.8, lineJoin: .round, lineCap: .round)
                )
            }

            // Each muscle drawn either at its highlighted tint or
            // at a faint baseline so the user reads the muscle map
            // even when nothing's lit up. A top-to-bottom gradient on
            // the fill adds a subtle rounded, three-dimensional read.
            for muscle in muscles {
                let path = BodyAnatomy.path(for: muscle).applying(scale)
                let highlight = highlights[muscle]
                let base = self.fill(for: highlight)
                let rect = path.boundingRect
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [base, base.opacity(0.62)]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
                context.stroke(
                    path,
                    with: .color(silhouetteStroke.opacity(highlight == nil ? 0.5 : 0.9)),
                    style: StrokeStyle(lineWidth: highlight == nil ? 0.5 : 1.0,
                                       lineJoin: .round)
                )
            }
        }
    }

    private func transform(for size: CGSize) -> CGAffineTransform {
        // Body coordinates are normalized to [0…1] × [0…2.4]. Scale
        // uniformly by the smaller of the two available dimensions
        // so the figure stays proportional across phone sizes.
        let widthScale = size.width
        let heightScale = size.height / 2.4
        let scale = min(widthScale, heightScale)
        let xOffset = (size.width - scale) / 2
        let yOffset = (size.height - scale * 2.4) / 2
        return CGAffineTransform(translationX: xOffset, y: yOffset)
            .scaledBy(x: scale, y: scale)
    }

    private func fill(for highlight: MuscleHighlight?) -> Color {
        guard let highlight else { return Color.white.opacity(0.04) }
        switch highlight {
        case .primary:
            return primaryColor.opacity(0.85)
        case .secondary:
            return secondaryColor.opacity(0.65)
        case .intensity(let value):
            // Clamp + gamma-curve so low-frequency muscles stay
            // visible without dominating: 0 → 8% opacity, 1 → 90%.
            let clamped = max(0, min(1, value))
            let curve = pow(clamped, 0.6)
            return heatmapHotColor.opacity(0.08 + curve * 0.82)
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for facing: Facing) -> Text {
        let lit = highlights.compactMap { (muscle, highlight) -> String? in
            guard !(facing == .front && muscle.isBack),
                  !(facing == .back && !muscle.isBack)
            else { return nil }
            switch highlight {
            case .primary:           return "\(muscle.rawValue) (primary)"
            case .secondary:         return "\(muscle.rawValue) (secondary)"
            case .intensity(let v):  return "\(muscle.rawValue) (\(Int(v * 100))%)"
            }
        }
        let view = facing == .front ? "Front view" : "Back view"
        if lit.isEmpty {
            return Text("\(view), no muscles highlighted")
        } else {
            return Text("\(view), highlighted: " + lit.joined(separator: ", "))
        }
    }
}

// MARK: - Convenience builders

extension MuscleMapView {
    /// Build the highlight payload for an exercise's primary +
    /// secondary muscle lists. Primary wins ties — if a muscle is
    /// listed in both arrays (rare but possible) the primary tint
    /// dominates.
    static func highlights(
        primaryRawMuscles: [String],
        secondaryRawMuscles: [String]
    ) -> [AnatomicalMuscle: MuscleHighlight] {
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        for muscle in AnatomicalMuscle.regions(forRawMuscles: secondaryRawMuscles) {
            map[muscle] = .secondary
        }
        for muscle in AnatomicalMuscle.regions(forRawMuscles: primaryRawMuscles) {
            map[muscle] = .primary
        }
        return map
    }

    /// Build the highlight payload for a `[muscle: frequency]` map
    /// (typically from `WeeklyMuscleHeatmap`). Frequencies are
    /// normalised against the max frequency so the most-trained
    /// muscle is fully lit and the rest scale down.
    static func intensityHighlights(
        from frequencies: [AnatomicalMuscle: Double]
    ) -> [AnatomicalMuscle: MuscleHighlight] {
        let maxFrequency = frequencies.values.max() ?? 0
        guard maxFrequency > 0 else { return [:] }
        return frequencies.reduce(into: [:]) { acc, pair in
            acc[pair.key] = .intensity(pair.value / maxFrequency)
        }
    }
}

#Preview("Empty (no workouts logged yet)") {
    MuscleMapView(highlights: [:])
        .padding()
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}

#Preview("Exercise detail (Bar Lateral Pulldown)") {
    MuscleMapView(highlights: MuscleMapView.highlights(
        primaryRawMuscles: ["lats"],
        secondaryRawMuscles: ["biceps", "middle back", "shoulders"]
    ))
    .padding()
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}

#Preview("Weekly heatmap") {
    MuscleMapView(highlights: MuscleMapView.intensityHighlights(from: [
        .chest:           1.0,
        .shouldersFront:  0.7,
        .shouldersBack:   0.7,
        .tricepsLeft:     0.5,
        .tricepsRight:    0.5,
        .quadricepsLeft:  0.9,
        .quadricepsRight: 0.9,
        .glutesLeft:      0.6,
        .glutesRight:     0.6,
    ]))
    .padding()
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
