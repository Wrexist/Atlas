import SwiftUI
import UIKit

/// Bundled start / middle / end pictures of an exercise, drawn on the same
/// grey figure as the muscle map with the worked muscles tinted. Only a
/// few exercises have them; everything else shows the muscle map alone.
enum ExerciseStepArt {
    /// Variants that move exactly like an exercise that has pictures.
    private static let aliases: [String: String] = [
        "Barbell_Full_Squat": "Barbell_Squat"
    ]

    static func assetNames(for exerciseID: String) -> [String] {
        let id = aliases[exerciseID] ?? exerciseID
        return (1...3)
            .map { "howto-\(id)-\($0)" }
            .filter { UIImage(named: $0) != nil }
    }

    /// The middle step — the clearest single frame of the movement — for
    /// list tiles. Nil when the exercise has no pictures.
    static func thumbnailName(for exerciseID: String) -> String? {
        let steps = assetNames(for: exerciseID)
        return steps.count > 1 ? steps[1] : steps.first
    }
}

/// The step pictures side by side at one shared scale, feet on a common
/// baseline, so the figure stays the same size from step to step. The
/// pictures have transparent backgrounds, so they sit on the card in both
/// light and dark mode.
struct ExerciseStepStrip: View {
    let assetNames: [String]
    var height: CGFloat = 150

    var body: some View {
        let sizes = assetNames.map { UIImage(named: $0)?.size ?? CGSize(width: 1, height: 1) }
        StepStripLayout(sizes: sizes, maxHeight: height, spacing: Spacing.md) {
            ForEach(Array(assetNames.enumerated()), id: \.offset) { index, name in
                Image(name)
                    .resizable()
                    .accessibilityLabel(Text("Step \(index + 1) of \(assetNames.count)"))
            }
        }
    }
}

/// Lays the pictures out with one scale factor for all of them: the
/// largest that keeps the tallest within `maxHeight` and the row within
/// the offered width. Narrower pictures are not stretched to fill a slot.
private struct StepStripLayout: Layout {
    let sizes: [CGSize]
    let maxHeight: CGFloat
    let spacing: CGFloat

    private var naturalWidth: CGFloat { sizes.reduce(0) { $0 + $1.width } }
    private var naturalHeight: CGFloat { sizes.map(\.height).max() ?? 1 }
    private var gaps: CGFloat { spacing * CGFloat(max(sizes.count - 1, 0)) }

    private func scale(for width: CGFloat?) -> CGFloat {
        let byHeight = maxHeight / max(naturalHeight, 1)
        guard let width else { return byHeight }
        return min(byHeight, max(width - gaps, 0) / max(naturalWidth, 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = scale(for: proposal.width)
        return CGSize(width: proposal.width ?? naturalWidth * s + gaps, height: naturalHeight * s)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let s = scale(for: bounds.width)
        let used = naturalWidth * s + gaps
        let slack = (bounds.width - used) / CGFloat(sizes.count + 1)
        var x = bounds.minX + slack
        for (subview, size) in zip(subviews, sizes) {
            let w = size.width * s, h = size.height * s
            subview.place(
                at: CGPoint(x: x, y: bounds.maxY - h),
                proposal: ProposedViewSize(width: w, height: h)
            )
            x += w + spacing + slack
        }
    }
}
