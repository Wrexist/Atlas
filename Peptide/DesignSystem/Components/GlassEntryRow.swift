import SwiftUI

/// The canonical tappable "entry row" used across the app — an icon in a
/// tinted circle, a title + subtitle, and a trailing chevron, on the
/// standard inset surface. One source of truth so these rows are
/// pixel-identical everywhere instead of each surface re-implementing the
/// same chrome (Profile tools, food/protocol entry cards, settings rows).
///
/// Subtitle is passed as a `Text` so callers keep their own localisation
/// (a `LocalizedStringResource`, a literal key, an interpolated string)
/// while the row owns the styling — font, colour, single-line shrink.
struct GlassEntryRow: View {
    let icon: String
    var iconGradient: [Color] = [
        AppColor.accentPrimary.opacity(0.45),
        AppColor.accentLight.opacity(0.25),
    ]
    let title: LocalizedStringKey
    let subtitle: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: iconGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    subtitle
                        .font(AppFont.scaled(12))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .insetRowBackground()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }
}

extension View {
    /// The standard inset-row / tool-tile background: the app's secondary
    /// surface at 55% with a hairline glass border. One source of truth for
    /// the fill repeated across ~23 row/card surfaces, so the look can't
    /// drift between them.
    func insetRowBackground(
        cornerRadius: CGFloat = Spacing.cardCornerRadius,
        border: Color = AppColor.glassBorder
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.sm) {
            GlassEntryRow(
                icon: "testtube.2",
                title: "Lab work",
                subtitle: Text("12 entries across 3 panels"),
                action: {}
            )
            GlassEntryRow(
                icon: "syringe.fill",
                title: "Reconstitution calculator",
                subtitle: Text("Vial mg + bac water → exact syringe units"),
                action: {}
            )
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
