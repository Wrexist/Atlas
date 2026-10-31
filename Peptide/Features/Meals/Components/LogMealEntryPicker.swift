import SwiftUI

/// Two-tile chooser that opens either the barcode scanner (for packaged
/// food) or the photo-based meal scanner (for plates and fresh meals),
/// with a full-width tile under them for scanning a whole shared table.
///
/// A paired Liquid Glass card: the icon sits on the same raised `IconTile`
/// as `GlassEntryRow` (the food-library entry above it), with the title +
/// subtitle stack underneath. The two tiles share one
/// `LiquidGlassContainer` so their glass renders as a single group.
struct LogMealEntryPicker: View {
    let onScanBarcode: () -> Void
    let onSnapPhoto: () -> Void
    var onScanTable: (() -> Void)?

    var body: some View {
        LiquidGlassContainer(spacing: Spacing.sm) {
            VStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    tile(
                        icon: "barcode.viewfinder",
                        title: "Scan barcode",
                        subtitle: "Packaged food",
                        accessibilityHint: "Opens the camera to scan a food barcode and log its nutrition.",
                        action: onScanBarcode
                    )
                    tile(
                        icon: "viewfinder.circle.fill",
                        title: "Scan meal photo",
                        subtitle: "Meals & plates",
                        accessibilityHint: "Opens the camera to photograph a meal for an AI-estimated nutrition breakdown.",
                        action: onSnapPhoto
                    )
                }
                if let onScanTable {
                    tableTile(action: onScanTable)
                }
            }
        }
    }

    private func tableTile(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                IconTile("square.grid.2x2.fill", size: 40)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Scan the whole table")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("One photo, every dish cut out")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan the whole table")
        .accessibilityHint("Opens the camera to photograph a shared table; each dish is cut out and estimated on its own.")
        .accessibilityAddTraits(.isButton)
    }

    private func tile(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        accessibilityHint: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                IconTile(icon, size: 40)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption2)
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
