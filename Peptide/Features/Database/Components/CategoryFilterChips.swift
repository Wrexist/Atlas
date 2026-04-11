import SwiftUI

struct CategoryFilterChips: View {
    let categories: [PeptideCategory]
    let selected: PeptideCategory?
    let onSelect: (PeptideCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                FilterChip(
                    title: "All",
                    isSelected: selected == nil,
                    color: AppColor.accentPrimary
                ) {
                    onSelect(nil)
                }

                ForEach(categories) { category in
                    FilterChip(
                        title: category.displayName,
                        icon: category.iconName,
                        isSelected: selected == category,
                        color: category.color
                    ) {
                        onSelect(category)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
    }
}

private struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(AppFont.footnote)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? color : AppColor.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                Capsule()
                    .fill(isSelected ? color.opacity(0.15) : AppColor.cardOverlay)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isSelected ? color.opacity(0.3) : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .buttonStyle(GlassPressStyle())
    }
}

private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(AppAnimation.springSnappy, value: configuration.isPressed)
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
