import SwiftUI

/// A compact overview with larger, single-side inspection and a non-spatial way
/// to select every trained muscle. Shared by session and history cards.
struct TrainingBodyExplorer: View {
    let highlights: [AnatomicalMuscle: MuscleHighlight]
    var primaryColor: Color = AppColor.trainingPrimaryMuscle
    var secondaryColor: Color = AppColor.trainingSecondaryMuscle
    let onIdentify: (AnatomicalMuscle) -> Void

    @State private var side: Side = .both
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Side: String, CaseIterable {
        case both = "Both", front = "Front", back = "Back"
        var orientation: MuscleMapView.Orientation {
            switch self {
            case .both: .both
            case .front: .front
            case .back: .back
            }
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Picker("Body view", selection: $side) {
                ForEach(Side.allCases, id: \.self) { side in
                    Text(side.rawValue).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("training-body-side")

            MuscleMapView(
                highlights: highlights,
                orientation: side.orientation,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onIdentify: onIdentify
            )
            .frame(maxWidth: side == .both ? .infinity : 340)
            .frame(maxWidth: .infinity)

            HStack {
                if side != .back { Text("Front").frame(maxWidth: .infinity) }
                if side != .front { Text("Back").frame(maxWidth: .infinity) }
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .accessibilityHidden(true)

            if !highlights.isEmpty {
                Menu {
                    ForEach(AnatomicalMuscle.allCases.filter { highlights[$0] != nil }, id: \.self) { muscle in
                        Button(muscle.displayName) { onIdentify(muscle) }
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "list.bullet")
                        Text("Explore trained muscles")
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                    }
                    .font(AppFont.subheadline)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: Spacing.smallCornerRadius))
                }
                .accessibilityIdentifier("explore-trained-muscles")
                .accessibilityHint("Choose a muscle to view its exercises and completed sets.")
            }
        }
        // A single body gives narrow layouts and large text more room.
        .onChange(of: dynamicTypeSize, initial: true) { _, size in
            if size.isAccessibilitySize && side == .both { side = .front }
        }
    }
}
