import SwiftUI

/// Promo card for Pro upsell and signature-feature surfaces: a warm glow
/// backdrop, a brand seal on the right, headline copy on the left, and a
/// small solid-ink "View" / "Unlock" pill, the app's "do this" mark. Sets
/// those surfaces visually apart from utility cards.
///
/// Generic over `Trailing` so the caller can replace the default
/// chevron glyph with a custom right-side element (the B logo,
/// product art, etc.) without forking the API.
struct PremiumPromoCard<Trailing: View>: View {
    let eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let ctaLabel: LocalizedStringKey?
    /// Optional eligibility note under the CTA. Used by the Biology tab's
    /// "Available for users 18+" gate; other surfaces leave it nil.
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
                            .font(AppFont.scaled(11, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(AppColor.textPrimary.opacity(0.65))
                    }
                    Text(title)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textPrimary.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let ctaLabel {
                        ctaPill(label: ctaLabel)
                            .padding(.top, Spacing.sm)
                    }

                    if let qualifier {
                        qualifierNote(label: qualifier)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
                    .frame(width: 70, height: 70)
            }
            .padding(Spacing.lg)
            .background {
                GlowBackdrop()
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.textPrimary.opacity(0.10), lineWidth: 0.5)
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    /// The same solid-ink pill as `GlassButton.primary`: the card's one
    /// action has to read as tappable, not as a disabled grey chip.
    private func ctaPill(label: LocalizedStringKey) -> some View {
        Text(label)
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(AppColor.inverseInk)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Capsule(style: .continuous).fill(AppColor.textPrimary))
    }

    /// An eligibility note, set as plain text so it can't be mistaken for
    /// a second button, and without a lock: the card invites an upgrade.
    private func qualifierNote(label: LocalizedStringKey) -> some View {
        Text(label)
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Spacing.xs)
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

/// A quiet, sculpted brand seal shared with the premium offer screens.
struct BrandGlyphMark: View {
    var body: some View {
        MilestoneArtwork(size: 70, style: .emblem, isActive: false)
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
