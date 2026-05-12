import SwiftUI

/// "Make it yours" onboarding step. Two-card display-mode picker on top
/// (Light / Dark) and a horizontal pill row of brand colours below. Both
/// choices write through to `ThemeManager.shared`, which persists the
/// values to UserDefaults; the picker view re-renders live as the user
/// taps so the selection ring follows the touch.
struct ThemeChoicePage: View {
    @Bindable var theme: ThemeManager

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            VStack(spacing: Spacing.sm) {
                Text("Make it yours.")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Choose your look. You can change this any time in Settings.")
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("DISPLAY MODE")

            HStack(spacing: Spacing.md) {
                displayModeCard(.light, icon: "sun.max.fill", label: "Light")
                displayModeCard(.dark, icon: "moon.fill", label: "Dark")
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
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textSecondary)
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(height: 30)

                Text(label)
                    .font(AppFont.headline)
                    .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? AppColor.accentPrimary.opacity(0.10)
                            : AppColor.surfaceSecondary.opacity(0.6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.accentPrimary.opacity(0.55) : AppColor.glassBorder,
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Color theme

    private var colorThemeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
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
            ZStack {
                Circle()
                    .fill(pillFill(for: themeColor))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .shadow(color: themeColor.primary.opacity(isSelected ? 0.55 : 0.0), radius: 8, y: 2)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? themeColor.primary.opacity(0.10)
                            : AppColor.surfaceSecondary.opacity(0.55)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? themeColor.primary.opacity(0.55) : AppColor.glassBorder,
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(themeColor.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // ShapeStyle isn't ViewBuilder-buildable — the if/else branches produce
    // distinct concrete types (LinearGradient vs Color), and Swift 6 no
    // longer auto-wraps them into a conforming opaque return. Erase to
    // AnyShapeStyle at the boundary so callers stay generic.
    private func pillFill(for themeColor: AppThemeColor) -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [themeColor.primary, themeColor.light],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
