import SwiftUI

/// Reusable "premium / aspirational" backdrop. The app's near-black
/// background plus a soft accent glow and a deterministic starfield —
/// the same recipe `PremiumPromoCard` uses for its upsell surfaces,
/// lifted into its own component so other premium surfaces (notably the
/// Biology tab) can sit on it without re-implementing the math.
///
/// Re-skinned from the original deep-purple gradient to the brand palette
/// (`AppColor.background` + themed accent glow) so the Biology tab and
/// premium cards read as the *same* app as every other near-black screen,
/// instead of a separate purple world.
///
/// Two knobs:
///   • `intensity` (0…1) scales glow brightness and star density. 1.0 =
///     the original promo-card look; 0.6 = a softer full-screen backdrop.
///   • `seed` lets a host pin a specific star arrangement so the same
///     screen renders identically across launches without shimmer between
///     body re-evaluations.
struct CosmicBackdrop: View {
    var intensity: Double = 1.0
    var seed: UInt64 = 0xA770_C175_DA75
    /// Approximate stars per 100×100pt block. The Canvas multiplies
    /// this by area to keep density consistent whether the
    /// backdrop covers a 200pt card or a full screen.
    var starDensityPer10k: Double = 14

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColor.background
            glow
            // A starfield only reads as "night sky" on a dark surface. In
            // light mode the same specks look like dust on the screen, so
            // the accent glow carries the premium feel alone.
            if colorScheme == .dark {
                starfield
            }
        }
    }

    /// Soft accent glow from the top — the brand's premium shimmer,
    /// replacing the old off-brand purple gradient so this backdrop sits
    /// in the same near-black palette as the rest of the app.
    private var glow: some View {
        let i = max(0, min(1, intensity))
        return RadialGradient(
            colors: [
                AppColor.accentPrimary.opacity(0.18 * i),
                AppColor.accentPrimary.opacity(0.05 * i),
                .clear,
            ],
            center: .top,
            startRadius: 0,
            endRadius: 560
        )
    }

    /// Deterministic starfield. Star count scales with the
    /// receiving area so a full-screen variant doesn't look
    /// thinner than the original promo card.
    private var starfield: some View {
        Canvas { ctx, size in
            let area = size.width * size.height
            let starCount = max(8, Int(starDensityPer10k * area / 10_000))
            var generator = SplitMix64(seed: seed)
            for i in 0..<starCount {
                let x = Double.random(in: 0...1, using: &generator) * size.width
                let y = Double.random(in: 0...1, using: &generator) * size.height
                let r = Double.random(in: 0.5...1.6, using: &generator)
                let opacity = Double.random(in: 0.2...0.6, using: &generator) * intensity
                // Most stars are neutral white; a few pick up the accent so
                // the field feels on-brand without reading as coloured noise.
                let tint: Color = (i % 6 == 0) ? AppColor.accentLight : .white
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Deterministic RNG

/// Tiny SplitMix64 — same one PremiumPromoCard had inline. Lifted
/// so both the promo card and the new full-screen backdrop share
/// one implementation. Foundation's SystemRNG would shuffle on
/// every render and the stars would shimmer.
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

#Preview("Full screen, soft") {
    ZStack {
        CosmicBackdrop(intensity: 0.55)
            .ignoresSafeArea()
        Text("Biology")
            .font(.system(size: 48, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
    }
}

#Preview("Card density") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        CosmicBackdrop()
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            .padding()
    }
    .preferredColorScheme(.dark)
}
