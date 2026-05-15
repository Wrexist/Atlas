import SwiftUI

/// One-line entry tile for the reconstitution calculator. Sits in
/// Profile between the Apple Health card and the Export section —
/// the "tools" cluster — so users discover it when they're already
/// in setup-and-config mode. Visually a smaller tile than the
/// other Profile cards to signal "utility" rather than "primary
/// affordance".
struct ReconstitutionEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.45),
                                    AppColor.accentLight.opacity(0.25),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconstitution calculator")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Vial mg + bac water → exact syringe units")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityLabel("Reconstitution calculator")
        .accessibilityHint("Opens the calculator for converting vial size, bacteriostatic water, and target dose into U-100 syringe units.")
    }
}
