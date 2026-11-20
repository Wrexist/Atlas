import SwiftUI

/// Horizontally scrolling equipment filter row. Same single-select
/// pattern and chip recipe as `MuscleGroupChipRow`, so the two rows in
/// one filter shelf read as one control — easy to swap to multi-select
/// once the user research justifies the complexity.
struct EquipmentChipRow: View {
    @Binding var selection: EquipmentKind?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.chipSpacing) {
                    GlassChip(
                        "Any equipment",
                        style: .prominent,
                        isSelected: selection == nil
                    ) {
                        selection = nil
                    }
                    ForEach(EquipmentKind.allCases) { kind in
                        GlassChip(
                            LocalizedStringKey(kind.displayName),
                            glyph: kind.glyph,
                            style: .prominent,
                            isSelected: selection == kind
                        ) {
                            selection = (selection == kind) ? nil : kind
                        }
                        .id(kind)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                // GlassChip's 44pt target overhangs its capsule; this keeps
                // that overhang inside the scroll view, which won't hit-test
                // past its own bounds.
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: selection) { _, kind in
                guard let kind else { return }
                AppAnimation.with(AppAnimation.springSnappy) {
                    proxy.scrollTo(kind, anchor: .center)
                }
            }
        }
    }
}
