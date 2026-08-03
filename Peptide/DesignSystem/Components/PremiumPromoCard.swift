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
    /// Optional qualifier pill rendered between subtitle and CTA.
    /// Used by the Biology tab's "Available for users 18+" gate;
    /// other surfaces leave it nil and the pill doesn't render.
    let qualifier: LocalizedStringKey?
    let onTap: () -> Void
    let trailing: () -> Trailing

    init(
        eyebrow: LocalizedStringKey? = nil,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        ctaLabel: LocalizedStringKey? = "View",
        qualifier: LocalizedStringKey? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.ctaLabel = ctaLabel
        self.qualifier = qualifier
        self.onTap = onTap
        self.trailing = trailing
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(AppColor.textPrimary.opacity(0.65))
                    }
                    Text(title)
                        .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textPrimary.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let qualifier {
                        qualifierPill(label: qualifier)
                            .padding(.top, Spacing.xs)
                    }

                    if let ctaLabel {
                        ctaPill(label: ctaLabel)
                            .padding(.top, qualifier == nil ? Spacing.xs : 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
                    .frame(width: 70, height: 70)
            }
            .padding(Spacing.lg)
            .background {
                // Backdrop lifted to its own component so the
                // Biology tab and future premium surfaces can sit
                // on the same starfield without duplicating the
                // gradient + Canvas dance.
                CosmicBackdrop()
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.textPrimary.opacity(0.10), lineWidth: 0.5)
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    private func ctaPill(label: LocalizedStringKey) -> some View {
        Text(label)
            .font(AppFont.scaled(11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(AppColor.textPrimary.opacity(0.15))
                    .overlay {
                        Capsule().strokeBorder(AppColor.textPrimary.opacity(0.25), lineWidth: 0.5)
                    }
            }
    }

    /// "Available for users 18+" style qualifier — quieter than
    /// the CTA pill so it reads as a regulatory / eligibility
    /// note, not a tappable action. Uses a lock glyph to suggest
    /// "this is gated".
    private func qualifierPill(label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(AppFont.scaled(8, weight: .heavy))
            Text(label)
                .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                .tracking(0.3)
        }
        .foregroundStyle(AppColor.textPrimary.opacity(0.85))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(AppColor.textPrimary.opacity(0.08))
                .overlay {
                    Capsule().strokeBorder(AppColor.textPrimary.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Default trailing convenience

extension PremiumPromoCard where Trailing == BrandGlyphMark {
    init(
        eyebrow: LocalizedStringKey? = nil,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        ctaLabel: LocalizedStringKey? = "View",
        qualifier: LocalizedStringKey? = nil,
        onTap: @escaping () -> Void
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            ctaLabel: ctaLabel,
            qualifier: qualifier,
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
            Color.clear
                .glassControl(
                    .rect(cornerRadius: 18),
                    border: AppColor.textPrimary.opacity(0.18),
                    interactive: false
                )
            Text("A")
                .font(AppFont.scaled(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.textPrimary.opacity(0.85))
        }
    }
}

// SplitMix64 + starfield Canvas moved to CosmicBackdrop.swift so
// the Biology tab can sit on the same backdrop without each
// premium surface re-implementing the math.

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
