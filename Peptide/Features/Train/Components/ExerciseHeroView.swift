import SwiftUI

/// An exercise's visual: the Atlas body, front and back, with the muscles
/// it trains marked — prime movers in the strong primary tint, assisting
/// muscles a lighter secondary wash — over a one-line legend naming them.
/// Catalog and custom exercises render the same way, from their muscles.
struct ExerciseHeroView: View {
    let exercise: Exercise?
    /// Share canvases render through ImageRenderer: no tap targets, no legend.
    var interactive = true

    var body: some View {
        if let exercise {
            let highlights = ExerciseAnatomyEngine.highlights(for: exercise)
            VStack(spacing: Spacing.sm) {
                MuscleMapView(
                    highlights: highlights,
                    primaryColor: AppColor.trainingPrimaryMuscle,
                    secondaryColor: AppColor.trainingSecondaryMuscle,
                    identifiesOnTap: interactive
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Muscle map for \(exercise.name)"))
                .accessibilityValue(Text(ExerciseMuscleLegend.summary(for: highlights)))
                if interactive {
                    ExerciseMuscleLegend(highlights: highlights)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(AppFont.statValue)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Exercise illustration unavailable")
        }
    }
}

/// Primary and secondary muscle names under the figure, one line each tier.
struct ExerciseMuscleLegend: View {
    let highlights: [AnatomicalMuscle: MuscleHighlight]

    var body: some View {
        HStack(spacing: Spacing.md) {
            tier(.primary, color: AppColor.trainingPrimaryMuscle)
            tier(.secondary, color: AppColor.trainingSecondaryMuscle)
        }
        .font(AppFont.caption2)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tier(_ tier: MuscleHighlight, color: Color) -> some View {
        let names = ExerciseAnatomyEngine.names(in: highlights, tier: tier)
        if !names.isEmpty {
            HStack(spacing: Spacing.xs) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(names.joined(separator: ", "))
                    .foregroundStyle(AppColor.textSecondary)
                    .truncationMode(.tail)
            }
            .layoutPriority(tier == .primary ? 1 : 0)
        }
    }

    static func summary(for highlights: [AnatomicalMuscle: MuscleHighlight]) -> String {
        let primary = ExerciseAnatomyEngine.names(in: highlights, tier: .primary)
        let secondary = ExerciseAnatomyEngine.names(in: highlights, tier: .secondary)
        var parts: [String] = []
        if !primary.isEmpty { parts.append(String(localized: "Primary: ") + primary.joined(separator: ", ")) }
        if !secondary.isEmpty { parts.append(String(localized: "Supporting: ") + secondary.joined(separator: ", ")) }
        return parts.isEmpty ? String(localized: "No mapped muscles") : parts.joined(separator: ". ")
    }
}

/// One side of the body zoomed to the band the exercise works — arms for a
/// curl, legs for a squat — so the marking reads at list-tile size.
struct ExerciseMuscleThumbnail: View {
    let highlights: [AnatomicalMuscle: MuscleHighlight]

    var body: some View {
        GeometryReader { geo in
            let side = ExerciseAnatomyEngine.preferredSide(for: highlights)
            let focus = ExerciseAnatomyEngine.focusRect(
                for: highlights, side: side,
                aspect: geo.size.width / max(geo.size.height, 1)
            )
            let width = geo.size.width / focus.width
            let height = geo.size.height / focus.height
            MuscleMapView(
                highlights: highlights,
                orientation: side == .front ? .front : .back,
                primaryColor: AppColor.trainingPrimaryMuscle,
                secondaryColor: AppColor.trainingSecondaryMuscle,
                identifiesOnTap: false
            )
            .frame(width: width, height: height)
            .offset(x: -focus.minX * width, y: -focus.minY * height)
        }
        .clipped()
        // Flattens the stack of masked, blurred figure copies into one
        // tile-sized layer, so a scrolling list composites one image per row.
        .drawingGroup()
    }
}
