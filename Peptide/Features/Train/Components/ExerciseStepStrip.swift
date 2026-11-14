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
}

/// The step pictures side by side, each with its step number underneath.
/// The pictures have transparent backgrounds, so they sit on the card in
/// both light and dark mode.
struct ExerciseStepStrip: View {
    let assetNames: [String]
    var height: CGFloat = 150

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.md) {
            ForEach(Array(assetNames.enumerated()), id: \.offset) { index, name in
                VStack(spacing: Spacing.xs) {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: height)
                    Text(verbatim: "\(index + 1)")
                        .font(AppFont.scaled(AppFont.Scale.caption, weight: .semibold, relativeTo: .caption1))
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Step \(index + 1) of \(assetNames.count)"))
            }
        }
    }
}
