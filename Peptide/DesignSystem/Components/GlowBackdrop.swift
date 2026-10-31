import SwiftUI

/// The premium upsell surface: the page colour with one soft light from
/// the top. Accent in dark, a warm peach dawn in light, where an accent
/// wash on off-white reads as a stain.
struct GlowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColor.background
            RadialGradient(
                colors: [tint.opacity(0.18), tint.opacity(0.05), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 560
            )
        }
    }

    private var tint: Color {
        colorScheme == .dark ? AppColor.accentPrimary : AppColor.paperGlow
    }
}

// MARK: - Deterministic RNG

/// Tiny SplitMix64, for drawings that scatter points and must not
/// shimmer between body re-evaluations the way the system RNG would.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    GlowBackdrop()
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        .padding()
}
