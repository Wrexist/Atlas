import SwiftUI

/// Shared empty-state surface used by the primary lists (Protocols,
/// Peptides, Insights, per-protocol dose log) so every "nothing to
/// show yet" reads with one premium visual rhythm instead of
/// scattered inline VStacks. Two styles:
///
///   • `.fullScreen` — hero treatment with a gradient icon medallion,
///     bright title in the primary text colour, optional primary
///     CTA + optional secondary hint. Used at the centre of an
///     otherwise blank scroll.
///   • `.compact` — small inline empty state for in-card surfaces
///     (Daily Plan, Health Correlation, detail panels). Reads as
///     muted helper text, not a hero.
///
/// Phase 35c rewrote the hero treatment — gradient medallion, glass
/// card backdrop, secondary action — so the half-dozen inline
/// `GlassCard { VStack { Image ... } }` empty states across the app
/// can collapse to one type without losing their warmth.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var accent: Color = AppColor.accentPrimary
    var action: Action? = nil
    /// Secondary hint or affordance below the primary CTA. Renders
    /// as a small uppercase text button without a background, so
    /// it reads as a "you can also…" rather than a competing CTA.
    var secondary: Action? = nil
    var style: Style = .fullScreen

    enum Style {
        case fullScreen
        case compact
    }

    struct Action {
        let title: LocalizedStringKey
        let icon: String?
        let perform: () -> Void

        init(title: LocalizedStringKey, icon: String? = nil, perform: @escaping () -> Void) {
            self.title = title
            self.icon = icon
            self.perform = perform
        }
    }

    var body: some View {
        switch style {
        case .fullScreen: heroContent
        case .compact:    compactContent
        }
    }

    // MARK: - Hero treatment

    private var heroContent: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.lg) {
                heroMedallion

                VStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(AppFont.title2)
                        .fontWeight(.heavy)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.sm)

                if let action {
                    GlassButton(
                        title: action.title,
                        icon: action.icon,
                        style: .primary,
                        isFullWidth: true
                    ) {
                        action.perform()
                    }
                    .padding(.top, Spacing.xs)
                }

                if let secondary {
                    Button(action: secondary.perform) {
                        HStack(spacing: Spacing.xs) {
                            if let icon = secondary.icon {
                                Image(systemName: icon)
                                    .font(AppFont.scaled(11, weight: .heavy))
                            }
                            Text(secondary.title)
                                .font(AppFont.scaled(13, weight: .heavy))
                                .tracking(0.4)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(AppColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
        .accessibilityElement(children: .combine)
    }

    /// Gradient-filled circle hosting the SF Symbol. The accent
    /// glow underneath gives the hero card depth without committing
    /// to a custom illustration per empty-state surface.
    private var heroMedallion: some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: 72, height: 72)
                .shadow(color: accent.opacity(0.45), radius: 12, y: 6)
            Image(systemName: icon)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - Compact treatment (in-card)

    private var compactContent: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(AppColor.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.lg)

            if let action {
                GlassButton(
                    title: action.title,
                    icon: action.icon,
                    style: .primary
                ) {
                    action.perform()
                }
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
    }
}

#Preview("With primary + secondary") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        EmptyStateView(
            icon: "list.clipboard.fill",
            title: "No protocols yet",
            message: "Create your first peptide protocol to start tracking doses, streaks, and compliance.",
            action: .init(title: "Create Protocol", icon: "plus", perform: {}),
            secondary: .init(title: "Browse the library", icon: "magnifyingglass", perform: {})
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("Tinted accent") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        EmptyStateView(
            icon: "chart.line.uptrend.xyaxis",
            title: "No data yet",
            message: "Log a few doses to see compliance, streaks, and correlation trends here.",
            accent: Color(red: 0.40, green: 0.74, blue: 0.92),
            action: .init(title: "Create a Protocol", icon: "plus", perform: {})
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("Compact (in-card)") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        GlassCard {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Try a different search term.",
                style: .compact
            )
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
