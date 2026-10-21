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
                HStack(spacing: Spacing.xs) {
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
                .padding(.vertical, Spacing.xs)
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
