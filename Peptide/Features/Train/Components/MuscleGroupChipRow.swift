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
                GlassChip(
                    "All",
                    style: .prominent,
                    isSelected: selection == nil
                ) {
                    selection = nil
                }
                ForEach(MuscleGroup.allCases) { group in
                    GlassChip(
                        LocalizedStringKey(group.displayName),
                        icon: group.symbolName,
                        style: .prominent,
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
}
