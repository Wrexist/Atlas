import SwiftUI

/// The canonical tappable "entry row" used across the app — an icon on a
/// raised `IconTile`, a title + optional subtitle, an optional trailing `Badge`
/// and a chevron, on the standard inset surface. One source of truth so
/// these rows are pixel-identical everywhere instead of each surface
/// re-implementing the same chrome (Profile tools, Library and Protocol
/// entries, food search, settings rows).
///
/// `GlassEntryRow` is the `Button` form. A row that pushes a navigation
/// destination wraps `GlassEntryRowLabel` in its own `NavigationLink` with
/// `ScalePressStyle(pressedScale: 0.98)`.
struct GlassEntryRow: View {
    private let label: GlassEntryRowLabel
    private let action: () -> Void

    init(
        icon: String,
        title: LocalizedStringKey,
        subtitle: Text? = nil,
        badge: Badge? = nil,
        action: @escaping () -> Void
    ) {
        label = GlassEntryRowLabel(icon: icon, title: title, subtitle: subtitle, badge: badge)
        self.action = action
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }
}

/// The visual body of `GlassEntryRow`, for rows whose trigger isn't a plain
/// `Button` (a `NavigationLink`).
///
/// Subtitle is passed as a `Text` so callers keep their own localisation
/// (a `LocalizedStringResource`, a literal key, an interpolated string)
/// while the row owns the styling.
struct GlassEntryRowLabel: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: Text?
    var badge: Badge?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The tile grows with its glyph, up to AX1 so it doesn't crowd out the
    /// title at the largest sizes.
    private var iconTypeSize: DynamicTypeSize { min(dynamicTypeSize, .accessibility1) }

    var body: some View {
        let tileSize = AppFont.scaledValue(40, in: iconTypeSize)
        HStack(spacing: Spacing.md) {
            IconTile(icon, size: tileSize)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let subtitle {
                    subtitle
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            if let badge {
                badge
            }

            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetRowBackground()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
        background { InsetRowFill(cornerRadius: cornerRadius, border: border) }
    }
}

/// Opaque under Reduce Transparency, like the legacy glass fill.
private struct InsetRowFill: View {
    let cornerRadius: CGFloat
    let border: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(reduceTransparency ? 1 : 0.55))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
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
                icon: "flask.fill",
                title: "Create your first protocol",
                subtitle: Text("Track doses, streaks, and adherence."),
                badge: Badge("Get started", style: .solid),
                action: {}
            )
            GlassEntryRow(icon: "gearshape.fill", title: "Settings", action: {})
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
