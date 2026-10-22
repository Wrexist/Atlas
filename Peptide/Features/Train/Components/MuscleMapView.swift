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
    /// Frequency-driven shade for the weekly heatmap, rendered on the
    /// green → yellow → orange → red → purple load ramp. `0.0` is a
    /// just-started green, `1.0` the most-trained purple.
    case intensity(Double)
}

/// The Atlas body (AnatomyV2 artwork) with a configurable set of muscles
/// tinted on it. Three modes:
///
/// - **Exercise** — pass a `[muscle: .primary | .secondary]` map. Prime
///   movers take the strong primary tint, assisting muscles a lighter wash.
/// - **Weekly heatmap** — pass `[muscle: .intensity(0…1)]`. Renders
///   each muscle on the load ramp: green for freshly-started work
///   climbing through yellow, orange and red to purple for the
///   most-trained muscle.
/// - **Empty** — pass `[:]` (or omit). Renders the bare body as a calm
///   baseline so the surface still reads as the user's body before
///   they've logged anything.
struct MuscleMapView: View {

    let highlights: [AnatomicalMuscle: MuscleHighlight]
    var orientation: Orientation = .both
    // The app's accent, not a hardcoded red/blue pair. Atlas ships five
    // brand ramps and the user picks one in onboarding; a fixed red
    // primary and blue secondary meant this screen disagreed with the tab
    // bar and every other surface the moment anyone chose a theme.
    var primaryColor: Color = AppColor.accentPrimary
    var secondaryColor: Color = AppColor.accentPrimary.opacity(0.45)
    /// When true the user can tap a muscle to identify it — the tapped
    /// head's name floats over the figure and `onIdentify` fires.
    var identifiesOnTap: Bool = true
    /// Called with the head the user tapped (e.g. to drive a detail sheet).
    var onIdentify: ((AnatomicalMuscle) -> Void)? = nil
    var selectedMuscle: AnatomicalMuscle? = nil

    /// The head the user last tapped, surfaced as a floating label.
    @State private var identified: AnatomicalMuscle? = nil

    enum Orientation {
        case front, back, both
    }

    private enum Facing { case front, back }

    var body: some View {
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
        .aspectRatio(TrainingAnatomy.aspect * (orientation == .both ? 2 : 1), contentMode: .fit)
        .overlay(alignment: .top) { identifyLabel }
    }

    // MARK: - Tap to identify

    /// Transparent hit-test layer over one figure, matched against the
    /// same paths that clip the tint.
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
                .font(AppFont.caption2.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 5)
                .background(Capsule().fill(AppColor.surfaceElevated))
                .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                .padding(.top, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func identify(at point: CGPoint, facing: Facing, size: CGSize) {
        let width = min(size.width, size.height * TrainingAnatomy.aspect)
        let height = width / TrainingAnatomy.aspect
        let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                          width: width, height: height)
        let hit = TrainingAnatomy.hitTest(point, in: rect, candidates:
            AnatomicalMuscle.allCases.filter { $0.isBack == (facing == .back) })
        // When a caller handles identification (e.g. to present a detail
        // sheet) defer to it; otherwise float the name label in-place.
        if let onIdentify {
            if let hit { onIdentify(hit) }
        } else {
            AppAnimation.with(AppAnimation.quick) { identified = hit }
        }
    }

    // MARK: - Figure

    /// The grayscale, fully-shaded body with each lit muscle re-tinted on
    /// a copy of itself. Unlit muscles read straight off the base image.
    private func figure(facing: Facing) -> some View {
        let base = facing == .front ? TrainingAnatomy.front : TrainingAnatomy.back
        let muscles = AnatomicalMuscle.allCases.filter { $0.isBack == (facing == .back) }
        return ZStack {
            Image(base)
                .resizable()
                .scaledToFit()
            // `colorMultiply` keeps the body's shadows and highlights while
            // pushing the hue to the tier colour — so the muscle looks lit,
            // not painted with a flat blob.
            ForEach(muscles, id: \.self) { muscle in
                if let highlight = highlights[muscle] {
                    Image(base)
                        .resizable()
                        .scaledToFit()
                        .colorMultiply(tintColor(for: highlight))
                        .opacity(tintStrength(for: highlight))
                        .mask {
                            TrainingMuscleShape(muscle: muscle)
                                .aspectRatio(TrainingAnatomy.aspect, contentMode: .fit)
                                .blur(radius: 0.65)
                        }
                }
            }
            if let selectedMuscle, selectedMuscle.isBack == (facing == .back) {
                TrainingMuscleShape(muscle: selectedMuscle)
                    .stroke(AppColor.textPrimary, lineWidth: 2)
                    .aspectRatio(TrainingAnatomy.aspect, contentMode: .fit)
                    .allowsHitTesting(false)
            }
        }
        .appAnimation(AppAnimation.quick, value: highlights)
    }

    /// Hue a lit muscle takes on.
    private func tintColor(for highlight: MuscleHighlight) -> Color {
        switch highlight {
        case .primary:          return primaryColor
        case .secondary:        return secondaryColor
        case .intensity(let v): return Self.heatColor(for: v)
        }
    }

    /// How strongly the tint reads over the shaded base — near-full for an
    /// exercise's prime mover, a clearly lighter wash for assisting
    /// muscles, and ramped by frequency for the weekly heatmap so a
    /// lightly-trained muscle is a faint wash and a hammered one saturated.
    private func tintStrength(for highlight: MuscleHighlight) -> Double {
        switch highlight {
        case .primary:           return 0.9
        case .secondary:         return 0.5
        case .intensity(let v):  return 0.3 + min(max(v, 0), 1) * 0.7
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for facing: Facing) -> Text {
        let lit = AnatomicalMuscle.allCases.compactMap { muscle -> String? in
            guard let highlight = highlights[muscle], muscle.isBack == (facing == .back) else { return nil }
            switch highlight {
            case .primary:           return "\(muscle.regionName), primary"
            case .secondary:         return "\(muscle.regionName), secondary"
            case .intensity(let v):  return "\(muscle.regionName), relative training score \(Int(max(0, min(1, v)) * 100)) out of 100"
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

// MARK: - Heat scale

extension MuscleMapView {
    /// Training-load colour ramp for `.intensity` highlights: green for a
    /// muscle the user has only just started hitting, through yellow,
    /// orange and red, to purple for the absolute most-trained muscle.
    private static let heatStops: [(position: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 0.20, 0.78, 0.35),  // green
        (0.25, 0.95, 0.80, 0.20),  // yellow
        (0.50, 0.97, 0.55, 0.15),  // orange
        (0.75, 0.93, 0.23, 0.23),  // red
        (1.00, 0.62, 0.27, 0.90),  // purple
    ]

    /// Colour on the load ramp for a normalised intensity (0…1),
    /// linearly interpolated between the five stops.
    static func heatColor(for intensity: Double) -> Color {
        let v = max(0, min(1, intensity))
        for i in 0..<(heatStops.count - 1) {
            let a = heatStops[i]
            let b = heatStops[i + 1]
            guard v <= b.position else { continue }
            let t = (v - a.position) / (b.position - a.position)
            return Color(
                red: a.r + (b.r - a.r) * t,
                green: a.g + (b.g - a.g) * t,
                blue: a.b + (b.b - a.b) * t
            )
        }
        let last = heatStops[heatStops.count - 1]
        return Color(red: last.r, green: last.g, blue: last.b)
    }

    /// The full ramp as a gradient, for legend capsules under heatmaps.
    static var heatLegendGradient: Gradient {
        Gradient(stops: heatStops.map {
            .init(color: Color(red: $0.r, green: $0.g, blue: $0.b), location: $0.position)
        })
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

    /// Build the highlight payload for a single exercise — see
    /// `ExerciseAnatomyEngine.highlights(for:)`.
    static func highlights(for exercise: Exercise) -> [AnatomicalMuscle: MuscleHighlight] {
        ExerciseAnatomyEngine.highlights(for: exercise)
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

// MARK: - Legend

/// Compact legend strip explaining the load ramp under a heatmap
/// figure: a green → yellow → orange → red → purple capsule between
/// two extreme labels.
struct MuscleHeatLegend: View {
    var lowLabel: String = "Less"
    var highLabel: String = "Most"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(lowLabel)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Capsule()
                .fill(LinearGradient(
                    gradient: MuscleMapView.heatLegendGradient,
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 6)
            Text(highLabel)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
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
