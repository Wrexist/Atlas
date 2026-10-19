import SwiftUI

struct CategoryFilterChips: View {
    let categories: [PeptideCategory]
    let selected: PeptideCategory?
    let onSelect: (PeptideCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                GlassChip("All", isSelected: selected == nil) {
                    handleSelect(nil)
                }

                ForEach(categories) { category in
                    GlassChip(
                        category.localizedTitle,
                        icon: category.iconName,
                        tint: category.color,
                        isSelected: selected == category
                    ) {
                        handleSelect(category)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
    }

    private func handleSelect(_ category: PeptideCategory?) {
        guard category != selected else { return }
        onSelect(category)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        CategoryFilterChips(
            categories: PeptideCategory.allCases,
            selected: .growth
        ) { _ in }
    }
    .preferredColorScheme(.dark)
}
