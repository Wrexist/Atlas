import SwiftUI

struct CategoryFilterChips: View {
    let categories: [PeptideCategory]
    let selected: PeptideCategory?
    let onSelect: (PeptideCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                GlassChip("All", isSelected: selected == nil) {
                    onSelect(nil)
                }

                ForEach(categories) { category in
                    GlassChip(
                        category.localizedTitle,
                        icon: category.iconName,
                        tint: category.color,
                        isSelected: selected == category
                    ) {
                        onSelect(category)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
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
