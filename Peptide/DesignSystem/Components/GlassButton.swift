import SwiftUI

enum GlassButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

/// The in-card button: sheets, empty states, settings rows. `.primary` is a
/// compact solid-ink pill, `.secondary` and `.destructive` are glass
/// capsules, `.ghost` is bare text. A screen's one full-width call to action
/// is `PrimaryCTAButton` instead.
struct GlassButton: View {
    let title: LocalizedStringKey
    var icon: String?
    var style: GlassButtonStyle = .primary
    var isFullWidth: Bool = false
    var action: () -> Void

    /// Set by any ancestor `.disabled(true)`. Without reading it the button
    /// looks fully enabled while silently ignoring taps — the state the
    /// bordered-prominent CTAs it replaced got for free from the system.
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var wrapsTitle: Bool { isFullWidth || dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            // `.ghost` is a bare text button — it gets no surface at all, so
            // it skips `glassControl` rather than passing a clear tint (which
            // would still paint the pre-iOS-26 fill).
            switch style {
            case .ghost:
                label
            case .primary:
                // A solid ink pill, the same "do this" mark as
                // PrimaryCTAButton and the selected segment. A tinted-glass
                // primary read as one more pastel chip on a calm page.
                label.background(Capsule(style: .continuous).fill(AppColor.textPrimary))
            // ScalePressStyle owns the press response; interactive glass
            // would run a second, competing scale on iOS 26.
            case .secondary:
                label.glassControl(.capsule, border: AppColor.glassBorder, interactive: false)
            case .destructive:
                // Kept at ~0.15: above that the tint stops reading as
                // coloured glass and starts reading as a flat painted button.
                label.glassControl(
                    .capsule,
                    tint: AppColor.destructive.opacity(0.15),
                    border: AppColor.destructive.opacity(0.3),
                    interactive: false
                )
            }
        }
        .buttonStyle(ScalePressStyle())
        .opacity(isEnabled ? 1 : AppOpacity.disabled)
    }

    private var label: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(AppFont.headline)
                .multilineTextAlignment(.center)
                // A hugging button squeezed by a sibling (two in an HStack)
                // broke a single Swedish word mid-word ("Ryg/g"); it shrinks
                // a little instead. Accessibility sizes keep wrapping, since
                // a long title there can't fit one line at any scale.
                .lineLimit(wrapsTitle ? nil : 1)
                .minimumScaleFactor(wrapsTitle ? 1 : 0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: isFullWidth ? .infinity : nil)
        .padding(.horizontal, isFullWidth ? Spacing.xl : Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(minHeight: Spacing.minimumHitTarget)
        .foregroundStyle(foregroundColor)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: AppColor.inverseInk
        case .secondary: AppColor.textPrimary
        case .ghost: AppColor.accentPrimary
        case .destructive: AppColor.destructiveInk
        }
    }
}

struct GlassIconButton: View {
    let icon: String
    let accessibilityLabel: LocalizedStringKey
    var size: CGFloat = Spacing.minimumHitTarget
    var tinted: Bool = false
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            // The circle is a fixed hit target, so the glyph stops growing
            // at xxxLarge instead of spilling past the glass edge; the
            // large content viewer covers the accessibility sizes.
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold, in: min(dynamicTypeSize, .xxxLarge)))
                .foregroundStyle(tinted ? AppColor.accentInkOnWash : AppColor.textPrimary)
                .frame(width: max(size, Spacing.minimumHitTarget),
                       height: max(size, Spacing.minimumHitTarget))
                .glassControl(
                    .circle,
                    tint: tinted ? AppColor.accentPrimary.opacity(0.18) : nil,
                    border: tinted ? AppColor.glassBorderActive : AppColor.glassBorder,
                    interactive: false
                )
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityShowsLargeContentViewer()
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            GlassButton(title: "Add to protocol", icon: "plus", style: .primary) {}
            GlassButton(title: "View Details", style: .secondary) {}
            GlassButton(title: "Cancel", style: .ghost) {}
            GlassButton(title: "Delete", icon: "trash", style: .destructive) {}
            GlassButton(title: "Full Width", style: .primary, isFullWidth: true) {}
            HStack(spacing: Spacing.md) {
                GlassIconButton(icon: "heart.fill", accessibilityLabel: "Favorite", tinted: true) {}
                GlassIconButton(icon: "square.and.arrow.up", accessibilityLabel: "Share") {}
                GlassIconButton(icon: "ellipsis", accessibilityLabel: "More options") {}
            }
        }
        .padding(Spacing.screenPadding)
    }
}
