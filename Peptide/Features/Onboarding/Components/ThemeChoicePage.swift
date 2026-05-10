import SwiftUI

/// "Make it yours" onboarding step. Two-card display-mode picker on top
/// (Light / Dark) and a horizontal pill row of brand colours below. Both
/// choices write through to `ThemeManager.shared`, which persists the
/// values to UserDefaults; the picker view re-renders live as the user
/// taps so the selection ring follows the touch.
struct ThemeChoicePage: View {
    @Bindable var theme: ThemeManager

    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Make it yours.")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Choose your look. Change it any time in Settings.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            displayModeSection

            colorThemeSection
        }
    }

    // MARK: - Display mode

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("DISPLAY MODE")

            HStack(spacing: Spacing.md) {
                displayModeCard(.light, icon: "sun.max", label: "Light")
                displayModeCard(.dark, icon: "moon", label: "Dark")
            }
        }
    }

    private func displayModeCard(
        _ mode: DisplayMode,
        icon: String,
        label: LocalizedStringKey
    ) -> some View {
        let isSelected = theme.displayMode == mode
        return Button {
            select(mode)
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textSecondary)
                    .symbolEffect(.bounce, value: isSelected)

                Text(label)
                    .font(AppFont.headline)
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textPrimary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Color theme

    private var colorThemeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("COLOR THEME")

            HStack(spacing: Spacing.sm) {
                ForEach(AppThemeColor.allCases) { themeColor in
                    colorThemeCard(themeColor)
                }
            }
        }
    }

    private func colorThemeCard(_ themeColor: AppThemeColor) -> some View {
        let isSelected = theme.theme == themeColor
        return Button {
            select(themeColor)
        } label: {
            VStack(spacing: Spacing.xs) {
                Capsule()
                    .fill(pillFill(for: themeColor))
                    .frame(height: 28)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 1)
                        }
                    }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(themeColor.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private func pillFill(for themeColor: AppThemeColor) -> some ShapeStyle {
        switch themeColor {
        case .purpleGradient:
            LinearGradient(
                colors: [themeColor.primary, themeColor.light],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            themeColor.primary
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.5)
            .foregroundStyle(AppColor.textSecondary)
    }

    private func select(_ mode: DisplayMode) {
        guard theme.displayMode != mode else { return }
        withAnimation(AppAnimation.springSnappy) {
            theme.displayMode = mode
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func select(_ color: AppThemeColor) {
        guard theme.theme != color else { return }
        withAnimation(AppAnimation.springSnappy) {
            theme.theme = color
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ThemeChoicePage(theme: ThemeManager.shared)
            .padding(.horizontal, Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
