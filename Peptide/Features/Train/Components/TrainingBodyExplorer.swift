import SwiftUI

/// A compact overview with larger, single-side inspection and a non-spatial way
/// to select every trained muscle. Shared by session and history cards.
struct TrainingBodyExplorer: View {
    let highlights: [AnatomicalMuscle: MuscleHighlight]
    var primaryColor: Color = AppColor.trainingPrimaryMuscle
    var secondaryColor: Color = AppColor.trainingSecondaryMuscle
    var legend: Legend = .roles
    let onIdentify: (AnatomicalMuscle) -> Void

    @State private var side: Side = .both
    @State private var selected: AnatomicalMuscle?
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

    enum Legend {
        case roles
        case intensity(low: String, high: String)
    }

    private var trainedGroups: [String] {
        Array(Set(highlights.keys.map(\.displayName))).sorted()
    }

    private func select(_ muscle: AnatomicalMuscle) {
        if side != .both { side = muscle.isBack ? .back : .front }
        selected = muscle
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
                onIdentify: { select($0) },
                selectedMuscle: selected
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
                switch legend {
                case .roles:
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.lg) { roleLabels }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: Spacing.sm) { roleLabels }
                    }
                    .font(AppFont.caption)
                case let .intensity(low, high):
                    MuscleHeatLegend(lowLabel: low, highLabel: high)
                }
            }

            if let selected {
                Button { onIdentify(selected) } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(selected.regionName)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(selectionDescription)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Label("View muscle history", systemImage: "chevron.right")
                            .font(AppFont.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(Spacing.md)
                    .background(AppColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: Spacing.smallCornerRadius))
                }
                .accessibilityIdentifier("selected-muscle-history")
            }

            if !highlights.isEmpty {
                Menu {
                    ForEach(trainedGroups, id: \.self) { group in
                        let regions = AnatomicalMuscle.allCases.filter {
                            $0.displayName == group && highlights[$0] != nil
                        }
                        if regions.count == 1, let muscle = regions.first {
                            Button(muscle.regionName) { select(muscle) }
                        } else {
                            Menu(group) {
                                ForEach(regions, id: \.self) { muscle in
                                    Button(muscle.regionName) { select(muscle) }
                                }
                            }
                        }
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
                .accessibilityHint("Select a muscle on the body, then open its history.")
            }
        }
        // A single body gives narrow layouts and large text more room.
        .onChange(of: dynamicTypeSize, initial: true) { _, size in
            if size.isAccessibilitySize && side == .both { side = .front }
        }
        .onChange(of: side) { _, side in
            if let selected, side != .both, selected.isBack != (side == .back) {
                self.selected = nil
            }
        }
        .onChange(of: highlights) { _, _ in selected = nil }
    }

    @ViewBuilder
    private var roleLabels: some View {
        Label("Primary", systemImage: "circle.fill").foregroundStyle(primaryColor)
        Label("Secondary", systemImage: "circle.lefthalf.filled").foregroundStyle(secondaryColor)
    }

    private var selectionDescription: String {
        guard let selected, let highlight = highlights[selected] else {
            return "No logged work in this view"
        }
        switch highlight {
        case .primary: return "Primary muscle"
        case .secondary: return "Secondary muscle"
        case .intensity: return "Highlighted from logged training"
        }
    }
}
