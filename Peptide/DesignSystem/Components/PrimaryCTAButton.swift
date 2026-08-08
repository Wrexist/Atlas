import SwiftUI

/// The solid call-to-action. `GlassButton` is the app's button — tinted
/// glass, accent ink, at home inside a card. This is the other thing: the
/// one action a screen exists for, painted rather than glazed, so it
/// outranks every glass control around it.
///
/// The fill is `ctaGradientStart → ctaGradientEnd`, the pair tuned to carry
/// `onAccent` ink at 4.5:1 in both schemes and every theme. An accent
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

    @Environment(\.isEnabled) private var isEnabled

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(AppColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .background { fill }
            // A tinted drop under a filled shape, not a halo behind a
            // glyph — the elevation idiom the accent medallions use.
            .shadow(color: AppColor.accentGlow, radius: 14, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
    }

    @ViewBuilder
    private var fill: some View {
        switch shape {
        case .capsule:
            Capsule().fill(gradient)
        case .rounded:
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(gradient)
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [AppColor.ctaGradientStart, AppColor.ctaGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
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
