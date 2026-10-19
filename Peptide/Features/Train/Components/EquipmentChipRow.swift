import SwiftUI

/// Horizontally scrolling equipment filter row. Same single-select
/// pattern as `MuscleGroupChipRow` — easy to swap to multi-select
/// once the user research justifies the complexity.
struct EquipmentChipRow: View {
    @Binding var selection: EquipmentKind?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                GlassChip(
                    "Any equipment",
                    tint: AppColor.textPrimary,
                    style: .prominent,
                    isSelected: selection == nil
                ) {
                    selection = nil
                }
                ForEach(EquipmentKind.allCases) { kind in
                    GlassChip(
                        LocalizedStringKey(kind.displayName),
                        icon: kind.symbolName,
                        tint: AppColor.textPrimary,
                        style: .prominent,
                        isSelected: selection == kind
                    ) {
                        selection = (selection == kind) ? nil : kind
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.xs)
        }
    }
}
