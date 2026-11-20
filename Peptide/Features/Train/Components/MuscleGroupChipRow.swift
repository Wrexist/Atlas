import SwiftUI

/// Horizontally scrolling chip row for the 9 muscle groups + "All".
/// Single-select with a clear "All" affordance — multi-select would
/// be a bigger UX (and a more useful one), but until we have a real
/// data set of session-by-muscle PRs to drive the bar charts, single
/// is the right complexity floor.
struct MuscleGroupChipRow: View {
    @Binding var selection: MuscleGroup?
    /// Space before the first chip: the screen gutter on its own, the chip
    /// gap when a control sits in front of the row.
    var leadingInset: CGFloat = Spacing.screenPadding

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.chipSpacing) {
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
                        .id(group)
                    }
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, Spacing.screenPadding)
                // GlassChip's 44pt target overhangs its capsule; this keeps
                // that overhang inside the scroll view, which won't hit-test
                // past its own bounds.
                .padding(.vertical, Spacing.sm)
            }
            // A pick made elsewhere (the body picker) can land on a chip
            // that's scrolled off-screen; bring it into view.
            .onChange(of: selection) { _, group in
                guard let group else { return }
                AppAnimation.with(AppAnimation.springSnappy) {
                    proxy.scrollTo(group, anchor: .center)
                }
            }
        }
    }
}
