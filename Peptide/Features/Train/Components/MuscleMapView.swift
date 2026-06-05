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
    /// Resting tint for an untrained muscle. Kept visible (not near-
    /// invisible) so the whole figure always reads as a sculpted body
    /// the way an anatomy chart does; training then warms each muscle.
    var muscleBaseline: Color = Color.white.opacity(0.15)
    /// Shadow colour for the muscle-separation grooves that give the
    /// figure its defined, three-dimensional read.
    var grooveColor: Color = Color.black.opacity(0.32)
    /// When true the user can tap a muscle to identify it — the tapped
    /// head's name floats over the figure and `onIdentify` fires.
    var identifiesOnTap: Bool = true
    /// Called with the head the user tapped (e.g. to drive a detail sheet).
    var onIdentify: ((AnatomicalMuscle) -> Void)? = nil

    /// The head the user last tapped, surfaced as a floating label.
    @State private var identified: AnatomicalMuscle? = nil

    enum Orientation {
        case front, back, both
    }

    var body: some View {
        // Prefer the photoreal asset pack when it's bundled; otherwise
        // draw the vector figure. Same API either way — see AnatomyAssets.
        if AnatomyAssets.isAvailable {
            assetMap
        } else {
            vectorMap
        }
    }

    // MARK: - Vector map

    private var vectorMap: some View {
        HStack(spacing: 0) {
            if orientation == .front || orientation == .both {
                figure(facing: .front)
                    .frame(maxWidth: .infinity)
                    .overlay { tapLayer(facing: .front) }
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel(for: .front))
            }
            if orientation == .back || orientation == .both {
                figure(facing: .back)
                    .frame(maxWidth: .infinity)
                    .overlay { tapLayer(facing: .back) }
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel(for: .back))
            }
        }
        .aspectRatio(orientation == .both ? BodyAnatomy.aspect * 2 : BodyAnatomy.aspect,
                     contentMode: .fit)
        .overlay(alignment: .top) { identifyLabel }
    }

    // MARK: - Tap to identify

    /// Transparent hit-test layer over one figure. Maps the tap location
    /// back into the figure's normalized space and finds the topmost muscle
    /// head whose path contains it.
    @ViewBuilder
    private func tapLayer(facing: Facing) -> some View {
        if identifiesOnTap {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        identify(at: location, facing: facing, size: geo.size)
                    }
            }
        }
    }

    @ViewBuilder
    private var identifyLabel: some View {
        if let identified {
            Text(identified.displayName)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(AppColor.surfaceElevated))
                .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                .padding(.top, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func identify(at point: CGPoint, facing: Facing, size: CGSize) {
        let scale = min(size.width, size.height / 2.4)
        guard scale > 0 else { return }
        let xOffset = (size.width - scale) / 2
        let yOffset = (size.height - scale * 2.4) / 2
        let p = CGPoint(x: (point.x - xOffset) / scale, y: (point.y - yOffset) / scale)
        let muscles = facing == .front
            ? AnatomicalMuscle.allCases.filter { !$0.isBack }
            : AnatomicalMuscle.allCases.filter { $0.isBack }
        // Last match = the head drawn on top where heads overlap.
        let hit = muscles.last { BodyAnatomy.path(for: $0).contains(p) }
        // When a caller handles identification (e.g. to present a detail
        // sheet) defer to it; otherwise float the name label in-place.
        if let onIdentify {
            if let hit { onIdentify(hit) }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { identified = hit }
        }
    }

    // MARK: - Asset map

    /// Photoreal rendering: a base body image with each trained muscle's
    /// mask tinted on top. Untrained muscles simply show the base image's
    /// own shading. Active only when `AnatomyAssets.isAvailable`.
    private var assetMap: some View {
        HStack(spacing: 0) {
            if orientation == .front || orientation == .both {
                assetFigure(facing: .front)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel(for: .front))
            }
            if orientation == .back || orientation == .both {
                assetFigure(facing: .back)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel(for: .back))
            }
        }
    }

    private func assetFigure(facing: Facing) -> some View {
        let base = facing == .front ? AnatomyAssets.bodyFront : AnatomyAssets.bodyBack
        let muscles = facing == .front
            ? AnatomicalMuscle.allCases.filter { !$0.isBack }
            : AnatomicalMuscle.allCases.filter { $0.isBack }
        return ZStack {
            // The grayscale, fully-shaded body. Untrained muscles read
            // straight off this layer.
            Image(base)
                .resizable()
                .scaledToFit()
            // For each trained muscle, re-tint a COPY of the shaded base
            // and clip it to that muscle's mask. `colorMultiply` keeps the
            // body's photoreal shadows/highlights while pushing the hue to
            // the training-intensity colour — so the muscle looks lit, not
            // painted with a flat blob.
            ForEach(muscles, id: \.self) { muscle in
                if let highlight = highlights[muscle] {
                    Image(base)
                        .resizable()
                        .scaledToFit()
                        .colorMultiply(tintColor(for: highlight))
                        .opacity(tintStrength(for: highlight))
                        .mask(
                            Image(AnatomyAssets.mask(for: muscle))
                                .resizable()
                                .scaledToFit()
                        )
                }
            }
        }
        .animation(AppAnimation.springSmooth, value: highlights)
    }

    /// Hue a trained muscle takes on in the asset renderer.
    private func tintColor(for highlight: MuscleHighlight) -> Color {
        switch highlight {
        case .primary:   return primaryColor
        case .secondary: return secondaryColor
        case .intensity: return heatmapHotColor
        }
    }

    /// How strongly the tint reads over the shaded base — full for an
    /// exercise's primary mover, softer for assisting muscles, and ramped
    /// by frequency for the weekly heatmap so a lightly-trained muscle is
    /// a faint wash and a hammered one is saturated.
    private func tintStrength(for highlight: MuscleHighlight) -> Double {
        switch highlight {
        case .primary:           return 1.0
        case .secondary:         return 0.75
        case .intensity(let v):  return 0.3 + min(max(v, 0), 1) * 0.7
        }
    }

    // MARK: - Figure

    private enum Facing { case front, back }

    @ViewBuilder
    private func figure(facing: Facing) -> some View {
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
                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
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
                // Top-lit volume: full tint at the top falling to a deeper
                // shade at the bottom reads as a rounded muscle belly.
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [base, base.opacity(0.45)]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
                context.stroke(
                    path,
                    with: .color(silhouetteStroke.opacity(highlight == nil ? 0.55 : 0.9)),
                    style: StrokeStyle(lineWidth: highlight == nil ? 0.6 : 1.0,
                                       lineJoin: .round)
                )
            }

            // Definition grooves — muscle separations laid over the fills
            // as soft shadow lines, clipped to the body so they never
            // bleed past the silhouette.
            var grooveContext = context
            grooveContext.clip(to: body)
            grooveContext.stroke(
                BodyAnatomy.grooves(front: facing == .front).applying(scale),
                with: .color(grooveColor),
                style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round)
            )
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
        guard let highlight else { return muscleBaseline }
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

    /// Build the highlight payload for a single exercise, using the
    /// exercise name to bias each muscle group toward the heads it
    /// actually emphasises (incline → clavicular pec, lateral raise →
    /// side delt, pushdown → lateral triceps…). A head is `.primary` when
    /// it's a strongly-weighted primary mover and `.secondary` otherwise.
    static func highlights(for exercise: Exercise) -> [AnatomicalMuscle: MuscleHighlight] {
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        for raw in exercise.secondaryMuscles {
            for (muscle, weight) in AnatomicalMuscle.headWeights(
                forRawMuscle: raw, exerciseName: exercise.name
            ) where weight >= 0.5 {
                map[muscle] = .secondary
            }
        }
        for raw in exercise.primaryMuscles {
            for (muscle, weight) in AnatomicalMuscle.headWeights(
                forRawMuscle: raw, exerciseName: exercise.name
            ) {
                if weight >= 0.75 {
                    map[muscle] = .primary
                } else if weight >= 0.4, map[muscle] == nil {
                    map[muscle] = .secondary
                }
            }
        }
        return map
    }

    /// Merge the per-exercise highlights for a whole session — primary
    /// wins over secondary for any head touched by more than one lift.
    static func highlights(forExercises exercises: [Exercise]) -> [AnatomicalMuscle: MuscleHighlight] {
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        for exercise in exercises {
            for (muscle, highlight) in highlights(for: exercise) {
                if highlight == .primary {
                    map[muscle] = .primary
                } else if map[muscle] == nil {
                    map[muscle] = .secondary
                }
            }
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
        .pecSternal:      1.0,
        .pecClavicular:   0.7,
        .deltAnterior:    0.7,
        .deltLateralFront: 0.7,
        .deltLateralBack: 0.7,
        .deltPosterior:   0.6,
        .tricepsLong:     0.5,
        .tricepsLateral:  0.5,
        .quadRectus:      0.9,
        .quadLateralis:   0.9,
        .quadMedialis:    0.9,
        .glutes:          0.6,
    ]))
    .padding()
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
