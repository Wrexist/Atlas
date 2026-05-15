import SwiftUI

/// Vertical bar with a draggable-looking dot at the user's most
/// recent reading. Bevel uses this next to every Health Monitor
/// card so the user sees "where today sits in my own range"
/// without parsing absolute numbers.
///
/// `fraction` is 0…1 along the p10→p90 personal range. `tint`
/// matches the BiometricCard's status colour so the indicator
/// reads as part of the same card, not an island.
struct PersonalRangeIndicator: View {
    /// 0…1 from the bottom of the bar (p10) to the top (p90).
    let fraction: Double
    let tint: Color
    var height: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottom) {
            // Track — soft pill behind the indicator line.
            Capsule()
                .fill(AppColor.surfaceElevated.opacity(0.6))
                .frame(width: 4, height: height)

            // Filled portion — from bottom up to fraction.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.4), tint],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 4, height: max(2, height * clampedFraction))

            // Dot at the latest-reading mark.
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle().strokeBorder(AppColor.background, lineWidth: 1.5)
                }
                .offset(y: -height * clampedFraction + 5)
        }
        .frame(width: 14, height: height)
    }

    private var clampedFraction: Double {
        max(0, min(1, fraction))
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HStack(spacing: Spacing.lg) {
            PersonalRangeIndicator(fraction: 0.15, tint: .blue)
            PersonalRangeIndicator(fraction: 0.50, tint: .green)
            PersonalRangeIndicator(fraction: 0.85, tint: .green)
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
