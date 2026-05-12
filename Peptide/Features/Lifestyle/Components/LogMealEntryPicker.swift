import SwiftUI

/// Two-tile chooser that opens either the barcode scanner (for
/// packaged food) or the photo-based meal scanner (for plates and
/// fresh meals). Replaces the single `MealScanBanner` that previously
/// sat at the top of the Lifestyle tab.
///
/// Each tile uses the same indigo→violet gradient as the old banner so
/// the meal-logging surface still reads as a single feature, just with
/// two clearly-labelled paths in.
struct LogMealEntryPicker: View {
    let onScanBarcode: () -> Void
    let onSnapPhoto: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            tile(
                icon: "barcode.viewfinder",
                title: "Scan barcode",
                subtitle: "Packaged food",
                accessibilityHint: "Opens the camera to scan a food barcode and log its nutrition.",
                action: onScanBarcode
            )
            tile(
                icon: "camera.fill",
                title: "Snap photo",
                subtitle: "Meals & plates",
                accessibilityHint: "Opens the camera to photograph a meal for an AI-estimated nutrition breakdown.",
                action: onSnapPhoto
            )
        }
    }

    private func tile(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                    }

                Spacer(minLength: Spacing.xs)

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .frame(minHeight: 108)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.310, green: 0.275, blue: 0.898), // #4F46E5
                                Color(red: 0.486, green: 0.227, blue: 0.929), // #7C3AED
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: AppColor.accentGlow, radius: 12, y: 5)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}
