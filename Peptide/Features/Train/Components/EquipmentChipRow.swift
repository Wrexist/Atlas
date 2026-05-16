import SwiftUI

/// Horizontally scrolling equipment filter row. Same single-select
/// pattern as `MuscleGroupChipRow` — easy to swap to multi-select
/// once the user research justifies the complexity.
struct EquipmentChipRow: View {
    @Binding var selection: EquipmentKind?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                AllChip(isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(EquipmentKind.allCases) { kind in
                    KindChip(
                        kind: kind,
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

    private struct AllChip: View {
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text("Any equipment")
                    .font(AppFont.chipText)
                    .foregroundStyle(isSelected ? AppColor.background : AppColor.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs + 2)
                    .background(
                        Capsule().fill(
                            isSelected ? AppColor.textPrimary.opacity(0.9) : AppColor.surfaceSecondary.opacity(0.6)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            isSelected ? Color.clear : AppColor.glassBorder,
                            lineWidth: 0.5
                        )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private struct KindChip: View {
        let kind: EquipmentKind
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(kind.displayName)
                        .font(AppFont.chipText)
                }
                .foregroundStyle(isSelected ? AppColor.background : AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs + 2)
                .background(
                    Capsule().fill(
                        isSelected ? AppColor.textPrimary.opacity(0.9) : AppColor.surfaceSecondary.opacity(0.6)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : AppColor.glassBorder,
                        lineWidth: 0.5
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(kind.displayName))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
