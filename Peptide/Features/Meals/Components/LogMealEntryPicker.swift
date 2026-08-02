import SwiftUI

/// Two-tile chooser that opens either the barcode scanner (for packaged
/// food) or the photo-based meal scanner (for plates and fresh meals).
///
/// Replaces the saturated purple banner with a paired Liquid Glass card:
/// a subtle accent-tinted background, a hierarchical SF Symbol icon at
/// the top, and the title + subtitle stack underneath. The two tiles
/// share a single `GlassEffectContainer` on iOS 26 so their glass
/// shapes can morph against each other on press.
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
                    title: "Snap photo",
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
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.55),
                                    accent.opacity(0.25),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .shadow(color: accent.opacity(0.35), radius: 8, y: 4)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.scaled(11, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }
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
