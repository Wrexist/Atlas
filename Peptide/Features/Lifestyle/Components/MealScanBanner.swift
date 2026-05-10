import SwiftUI

/// Tall gradient banner that opens the Claude-Vision meal scanner. The
/// gradient is hard-coded to the spec hexes (#4F46E5 → #7C3AED) so it
/// reads identically across themes — this banner is a marketing
/// surface, not an accent-tinted control.
struct MealScanBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                    }

                Text("Meal Scan")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.310, green: 0.275, blue: 0.898), // #4F46E5
                                Color(red: 0.486, green: 0.227, blue: 0.929), // #7C3AED
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: AppColor.accentGlow, radius: 14, y: 6)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meal Scan")
        .accessibilityHint("Opens the camera to scan a meal and estimate calories and macros.")
        .accessibilityAddTraits(.isButton)
    }
}
