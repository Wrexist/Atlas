import SwiftUI

/// The screen's full-width call to action: the one action a screen exists
/// for. `GlassButton` is the in-card control, and its `.primary` style is a
/// compact solid-ink pill; this is the full-width version with the CTA
/// gradient and drop shadow, so it outranks every control around it.
///
/// The fill is `ctaGradientStart → ctaGradientEnd`: an ink pill in light
/// mode, a near-white pill in dark, carrying `inverseInk` well past 4.5:1 in
/// both schemes and every theme. An accent
/// gradient cannot do this job — `accentPrimary` and `accentLight` are ink
/// colours, and near-white on them lands as low as 1.3:1, which is why
/// `design-lint`'s `accent-gradient-fill` rule rejects that construct.
struct PrimaryCTAButton: View {
    let title: LocalizedStringKey
    var icon: String?
    /// `.capsule` for a standalone action at the foot of a sheet;
    /// `.rounded` when the button sits in a column of cards and should
    /// share their corner radius.
    var shape: Shape = .capsule
    var action: () -> Void

    enum Shape {
        case capsule
        case rounded
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppFont.scaled(16, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AppFont.scaled(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .primaryCTAChrome(shape: shape)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
    }
}

extension View {
    /// The painted fill, glow, hit target and disabled state of
    /// `PrimaryCTAButton`, for a CTA whose label it can't express (the
    /// paywall's two-line price button). Apply it to the button's label.
    func primaryCTAChrome(shape: PrimaryCTAButton.Shape = .capsule) -> some View {
        modifier(PrimaryCTAChrome(shape: shape))
    }
}

private struct PrimaryCTAChrome: ViewModifier {
    let shape: PrimaryCTAButton.Shape

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            // Disabled, it drops to the track with tertiary ink — the same
            // state as `GlassButton`'s primary pill — rather than fading the
            // whole pill, label and all, into a low-contrast grey slab.
            .foregroundStyle(isEnabled ? AppColor.inverseInk : AppColor.textTertiary)
            // A spinner in the label follows the ink, so it stays visible
            // on the grey disabled fill.
            .tint(isEnabled ? AppColor.inverseInk : AppColor.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background { fill }
            // A tinted drop under a filled shape, not a halo behind a
            // glyph — the elevation idiom the accent medallions use. A
            // disabled button sits flat.
            .shadow(color: isEnabled ? AppColor.ctaGlow : .clear, radius: 14, y: 6)
    }

    @ViewBuilder
    private var fill: some View {
        switch shape {
        case .capsule:
            Capsule().fill(fillStyle)
        case .rounded:
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(fillStyle)
        }
    }

    private var fillStyle: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(AppColor.track) }
        return AnyShapeStyle(LinearGradient(
            colors: [AppColor.ctaGradientStart, AppColor.ctaGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
        ))
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        PrimaryCTAButton(title: "Start workout", icon: "play.fill", shape: .rounded) {}
        PrimaryCTAButton(title: "Add habit", icon: "plus") {}
        PrimaryCTAButton(title: "Add habit", icon: "plus") {}
            .disabled(true)
    }
    .padding(Spacing.screenPadding)
    .background(AppColor.background)
}
