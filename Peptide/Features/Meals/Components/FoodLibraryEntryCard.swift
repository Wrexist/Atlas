import SwiftUI

/// Prominent search-shaped entry that opens the food library. Sits
/// above the barcode/photo tile picker as the headline path —
/// covers the everyday "I know what I ate, just need to type it" flow
/// that the two scanners require physical artifacts (a barcode, a
/// plate) to handle.
///
/// Visually a faux-search-bar tile: leading magnifier, placeholder copy,
/// trailing chevron. Liquid-glass treatment matches the rest of the
/// section. Not a real TextField — tapping anywhere on the tile opens
/// the full sheet, where the actual search field auto-focuses.
struct FoodLibraryEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.55),
                                    AppColor.accentLight.opacity(0.30),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "magnifyingglass")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .shadow(color: AppColor.accentPrimary.opacity(0.35), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Search the food library")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Type a food, brand, or meal — log without scanning")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search the food library")
        .accessibilityHint("Opens a searchable list of foods you can log without scanning a barcode.")
        .accessibilityAddTraits(.isButton)
    }
}
