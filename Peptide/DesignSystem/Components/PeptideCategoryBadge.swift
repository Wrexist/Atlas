import SwiftUI

struct PeptideCategoryBadge: View {
    let category: PeptideCategory

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: category.iconName)
                .font(AppFont.scaled(11, weight: .semibold))

            Text(category.localizedTitle)
                .font(AppFont.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule()
                .fill(category.color.opacity(0.15))
                .overlay {
                    Capsule()
                        .strokeBorder(category.color.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}
