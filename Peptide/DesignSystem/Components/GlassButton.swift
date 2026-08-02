import SwiftUI

enum GlassButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

/// The app's one button. Every CTA — paywall, sheets, empty states, settings
/// rows — routes through this so there's a single press response, a single
/// glass recipe, and a single set of accent weights.
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

    var body: some View {
        Button(action: action) {
            // `.ghost` is a bare text button — it gets no surface at all, so
            // it skips `glassControl` rather than passing a clear tint (which
            // would still paint the pre-iOS-26 fill).
            if style == .ghost {
                label
            } else {
                label.glassControl(.capsule, tint: tint, border: border)
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    private var label: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(AppFont.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: isFullWidth ? .infinity : nil)
        .padding(.horizontal, isFullWidth ? Spacing.xl : Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(minHeight: Spacing.minimumHitTarget)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1 : 0.4)
    }

    /// Kept at ~0.15–0.18. Above that the tint stops reading as coloured glass
    /// and starts reading as a flat painted button — the previous 0.30–0.35
    /// values were the reason tinted controls looked opaque on iOS 26.
    private var tint: Color? {
        switch style {
        case .primary: AppColor.accentPrimary.opacity(0.18)
        case .secondary: nil
        case .ghost: nil
        case .destructive: AppColor.destructive.opacity(0.15)
        }
    }

    private var border: Color {
        switch style {
        case .primary: AppColor.glassBorderActive
        case .secondary: AppColor.glassBorder
        case .ghost: .clear
        case .destructive: AppColor.destructive.opacity(0.3)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: AppColor.accentLight
        case .secondary: AppColor.textPrimary
        case .ghost: AppColor.accentPrimary
        case .destructive: AppColor.destructive
        }
    }
}

struct GlassIconButton: View {
    let icon: String
    let accessibilityLabel: LocalizedStringKey
    var size: CGFloat = Spacing.minimumHitTarget
    var tinted: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(tinted ? AppColor.accentLight : AppColor.textPrimary)
                .frame(width: max(size, Spacing.minimumHitTarget),
                       height: max(size, Spacing.minimumHitTarget))
                .glassControl(
                    .circle,
                    tint: tinted ? AppColor.accentPrimary.opacity(0.18) : nil,
                    border: tinted ? AppColor.glassBorderActive : AppColor.glassBorder
                )
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppAnimation.springSnappy, value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            GlassButton(title: "Add to Protocol", icon: "plus", style: .primary) {}
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
