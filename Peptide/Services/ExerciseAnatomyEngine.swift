import CoreGraphics
import Foundation

/// An exercise drawn as the Atlas body with its work marked: which heads
/// light and at which tier, which side of the figure carries the lift, and
/// which part of the artwork a small tile should zoom to so a curl reads as
/// arms and a squat as legs at 44 pt. Pure geometry over the AnatomyV2
/// regions, so every surface crops and tints the same way.
enum ExerciseAnatomyEngine {

    enum Side: Sendable, Equatable {
        case front, back
    }

    /// How much a lit head counts when choosing the side to show.
    static let primaryWeight = 1.0
    static let secondaryWeight = 0.35

    /// Artwork size the region coordinates are authored against.
    private static let artwork = CGSize(width: 1024, height: 1536)

    /// The heads one exercise lights, specialised by its name (incline →
    /// clavicular pec, pushdown → lateral triceps…). A head is primary when
    /// it is a strongly-weighted prime mover and secondary otherwise.
    static func highlights(for exercise: Exercise) -> [AnatomicalMuscle: MuscleHighlight] {
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        var primaryWeights: [AnatomicalMuscle: Double] = [:]
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
                primaryWeights[muscle] = max(primaryWeights[muscle] ?? 0, weight)
                if weight >= 0.75 {
                    map[muscle] = .primary
                } else if weight >= 0.4, map[muscle] == nil {
                    map[muscle] = .secondary
                }
            }
        }
        // A prime mover always shows as one: a shoulder-tagged "Seated
        // Dumbbell Press" reads as a horizontal press to the name cues,
        // which would otherwise leave it with supporting tint only.
        if !map.values.contains(.primary), let strongest = primaryWeights.values.max() {
            for (muscle, weight) in primaryWeights where weight >= strongest {
                map[muscle] = .primary
            }
        }
        return map
    }

    /// The side of the body that carries most of the stimulus. Front wins a
    /// tie, and an empty map shows the front.
    static func preferredSide(for highlights: [AnatomicalMuscle: MuscleHighlight]) -> Side {
        var front = 0.0
        var back = 0.0
        for (muscle, highlight) in highlights {
            let weight = highlight == .primary ? primaryWeight : secondaryWeight
            if muscle.isBack { back += weight } else { front += weight }
        }
        return back > front ? .back : .front
    }

    /// User-facing names of the heads lit at one tier, deduplicated (three
    /// quad heads read "Quads" once) and in head order.
    static func names(in highlights: [AnatomicalMuscle: MuscleHighlight], tier: MuscleHighlight) -> [String] {
        var seen = Set<String>()
        return AnatomicalMuscle.allCases.compactMap { muscle in
            guard highlights[muscle] == tier, seen.insert(muscle.displayName).inserted else { return nil }
            return muscle.displayName
        }
    }

    /// Unit rect of the artwork (0…1 on both axes) a tile of `aspect`
    /// (width ÷ height) should show: the lit regions on `side` with a margin,
    /// at least `minimumHeight` of the figure tall, grown to the tile's shape
    /// and kept inside the artwork. With nothing lit on that side it frames
    /// the torso and thighs, where most lifts live.
    static func focusRect(
        for highlights: [AnatomicalMuscle: MuscleHighlight],
        side: Side,
        aspect: Double,
        regions: [String: [[Double]]] = TrainingAnatomy.regions,
        margin: Double = 0.03,
        minimumHeight: Double = 0.2
    ) -> CGRect {
        let lit = highlights.keys.filter { $0.isBack == (side == .back) }
        let points = lit.flatMap { regions[$0.rawValue] ?? [] }.filter { $0.count == 2 }
        let xs = points.flatMap { [$0[0], 2 * TrainingAnatomy.mirrorAxis - $0[0]] }
        let ys = points.map { $0[1] }
        var box = CGRect(x: 0.25, y: 0.15, width: 0.5, height: 0.5)
        if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
            // The same margin in pixels on both axes.
            box = CGRect(x: minX / artwork.width, y: minY / artwork.height,
                         width: (maxX - minX) / artwork.width,
                         height: (maxY - minY) / artwork.height)
                .insetBy(dx: -margin * artwork.height / artwork.width, dy: -margin)
        }
        if box.height < minimumHeight {
            box = box.insetBy(dx: 0, dy: (box.height - minimumHeight) / 2)
        }
        return fitted(box, aspect: max(aspect, 0.01))
    }

    /// Grows `box` to `aspect` in artwork pixels, then keeps it inside the
    /// unit square — shrinking the overflowing axis only when the artwork
    /// itself is narrower than the tile.
    private static func fitted(_ box: CGRect, aspect: Double) -> CGRect {
        let ratio = artwork.width / artwork.height
        var width = box.width
        var height = box.height
        if width * ratio / height < aspect {
            width = aspect * height / ratio
        } else {
            height = width * ratio / aspect
        }
        if width > 1 {
            width = 1
            height = min(1, ratio / aspect)
        }
        if height > 1 {
            height = 1
            width = min(1, aspect / ratio)
        }
        let x = min(max(box.midX - width / 2, 0), 1 - width)
        let y = min(max(box.midY - height / 2, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
