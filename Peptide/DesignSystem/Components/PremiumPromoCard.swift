import SwiftUI

/// Cosmic-backdrop promo card — Bevel's "Upgrade to Bevel Pro" and
/// "View Your Biological Age" cards use this exact pattern: a
/// deep-purple gradient with a faint starfield, a brand glyph on the
/// right, headline copy on the left, and a small "View" / "Unlock"
/// pill. Sets Pro upsell + signature-feature surfaces visually
/// apart from utility cards.
///
/// Generic over `Trailing` so the caller can replace the default
/// chevron glyph with a custom right-side element (the B logo,
/// product art, etc.) without forking the API.
struct PremiumPromoCard<Trailing: View>: View {
    let eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let ctaLabel: LocalizedStringKey?
    let onTap: () -> Void
    let trailing: () -> Trailing

    init(
        eyebrow: LocalizedStringKey? = nil,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        ctaLabel: LocalizedStringKey? = "View",
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.ctaLabel = ctaLabel
        self.onTap = onTap
        self.trailing = trailing
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let ctaLabel {
                        ctaPill(label: ctaLabel)
                            .padding(.top, Spacing.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
                    .frame(width: 70, height: 70)
            }
            .padding(Spacing.lg)
            .background {
                ZStack {
                    cosmicGradient
                    starfield
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    private func ctaPill(label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Color.white.opacity(0.15))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    }
            }
    }

    private var cosmicGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.08, blue: 0.22),
                Color(red: 0.18, green: 0.13, blue: 0.36),
                Color(red: 0.32, green: 0.20, blue: 0.48),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle scattered-dot pattern that reads as a starfield without
    /// shipping an asset. Deterministic positions so the same card
    /// always looks the same — no shimmer across re-renders.
    private var starfield: some View {
        Canvas { ctx, size in
            // Seeded PRNG-equivalent — same positions every render.
            var generator = SplitMix64(seed: 0xA770_C175_DA75)
            for _ in 0..<26 {
                let x = Double.random(in: 0...1, using: &generator) * size.width
                let y = Double.random(in: 0...1, using: &generator) * size.height
                let r = Double.random(in: 0.5...1.6, using: &generator)
                let opacity = Double.random(in: 0.25...0.7, using: &generator)
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Default trailing convenience

extension PremiumPromoCard where Trailing == BrandGlyphMark {
    init(
        eyebrow: LocalizedStringKey? = nil,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        ctaLabel: LocalizedStringKey? = "View",
        onTap: @escaping () -> Void
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            ctaLabel: ctaLabel,
            onTap: onTap,
            trailing: { BrandGlyphMark() }
        )
    }
}

/// Soft glass "A" mark — stand-in for the brand glyph until a real
/// asset is wired. Sits in the trailing slot so the cosmic card
/// reads as a product card, not a hero banner.
struct BrandGlyphMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            Text("A")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }
}

// MARK: - Deterministic RNG

/// Tiny SplitMix64 implementation so the starfield reproduces
/// across launches without shipping an asset. Foundation's
/// `SystemRandomNumberGenerator` would shuffle on every render and
/// the dots would shimmer.
private struct SplitMix64: RandomNumberGenerator {
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
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            PremiumPromoCard(
                eyebrow: "ATLAS PRO",
                title: "View Your Biological Age",
                subtitle: "Track how you're aging and discover which habits move your Bio Age.",
                onTap: {}
            )
            PremiumPromoCard(
                title: "Upgrade to Atlas Pro",
                subtitle: "Get more out of your data with AI insights and weekly summaries.",
                onTap: {}
            )
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
