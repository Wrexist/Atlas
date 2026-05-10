import SwiftUI

enum GlassButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

struct GlassButton: View {
    let title: LocalizedStringKey
    var icon: String?
    var style: GlassButtonStyle = .primary
    var isFullWidth: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
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
            .foregroundStyle(foregroundColor)
            .background {
                switch style {
                case .primary:
                    Capsule()
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Capsule()
                                .fill(AppColor.accentPrimary.opacity(0.3))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                case .secondary:
                    Capsule()
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Capsule()
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                case .ghost:
                    Color.clear
                case .destructive:
                    Capsule()
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Capsule()
                                .fill(AppColor.destructive.opacity(0.2))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(AppColor.destructive.opacity(0.3), lineWidth: 0.5)
                        }
                }
            }
            .liquidGlass(
                .capsule,
                tint: style == .primary ? AppColor.accentPrimary.opacity(0.35) : nil,
                interactive: true
            )
        }
        .buttonStyle(GlassPressStyle())
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
    var size: CGFloat = 44
    var tinted: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tinted ? AppColor.accentLight : AppColor.textPrimary)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Circle()
                                .fill(tinted ? AppColor.glassTint : AppColor.cardOverlay)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    tinted ? AppColor.glassBorderActive : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                        }
                }
                .liquidGlass(
                    .circle,
                    tint: tinted ? AppColor.accentPrimary.opacity(0.32) : nil,
                    interactive: true
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
    .preferredColorScheme(.dark)
}
