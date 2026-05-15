import SwiftUI

/// Horizontally scrolling chip row for the 9 muscle groups + "All".
/// Single-select with a clear "All" affordance — multi-select would
/// be a bigger UX (and a more useful one), but until we have a real
/// data set of session-by-muscle PRs to drive the bar charts, single
/// is the right complexity floor.
struct MuscleGroupChipRow: View {
    @Binding var selection: MuscleGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                AllChip(isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(MuscleGroup.allCases) { group in
                    GroupChip(
                        group: group,
                        isSelected: selection == group
                    ) {
                        selection = (selection == group) ? nil : group
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
                Text("All")
                    .font(AppFont.chipText)
                    .foregroundStyle(isSelected ? AppColor.background : AppColor.textPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs + 2)
                    .background(
                        Capsule().fill(
                            isSelected ? AppColor.accentPrimary : AppColor.surfaceSecondary.opacity(0.6)
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

    private struct GroupChip: View {
        let group: MuscleGroup
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: group.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(group.displayName)
                        .font(AppFont.chipText)
                }
                .foregroundStyle(isSelected ? AppColor.background : AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs + 2)
                .background(
                    Capsule().fill(
                        isSelected ? AppColor.accentPrimary : AppColor.surfaceSecondary.opacity(0.6)
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
            .accessibilityLabel(Text(group.displayName))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
