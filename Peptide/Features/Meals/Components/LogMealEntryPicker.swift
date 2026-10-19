import SwiftUI

/// Two-tile chooser that opens either the barcode scanner (for packaged
/// food) or the photo-based meal scanner (for plates and fresh meals).
///
/// A paired Liquid Glass card: the icon sits on the same flat tinted tile
/// as `GlassEntryRow` (the food-library entry above it), with the title +
/// subtitle stack underneath. The two tiles share one
/// `LiquidGlassContainer` so their glass renders as a single group.
struct LogMealEntryPicker: View {
    let onScanBarcode: () -> Void
    let onSnapPhoto: () -> Void

    var body: some View {
        LiquidGlassContainer(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                tile(
                    icon: "barcode.viewfinder",
                    title: "Scan barcode",
                    subtitle: "Packaged food",
                    accent: AppColor.accentLight,
                    accessibilityHint: "Opens the camera to scan a food barcode and log its nutrition.",
                    action: onScanBarcode
                )
                tile(
                    icon: "viewfinder.circle.fill",
                    title: "Scan meal photo",
                    subtitle: "Meals & plates",
                    accent: AppColor.accentPrimary,
                    accessibilityHint: "Opens the camera to photograph a meal for an AI-estimated nutrition breakdown.",
                    action: onSnapPhoto
                )
            }
        }
    }

    private func tile(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        accent: Color,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(accent.opacity(0.18))
                    }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .frame(minHeight: 108)
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}
