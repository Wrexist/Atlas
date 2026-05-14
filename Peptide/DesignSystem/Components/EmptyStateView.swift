import SwiftUI

/// Shared empty-state surface used by the primary lists (Protocols, Peptides,
/// per-protocol dose log) so they all read with the same visual rhythm
/// instead of three slightly-different inline VStacks. Optional `action`
/// renders a primary `GlassButton` underneath the copy.
///
/// Pass `style: .compact` for in-card empty states (Daily Plan, Health
/// Correlation, inline detail panels) where the full-bleed treatment
/// would overpower the surrounding card.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: Action? = nil
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
        VStack(spacing: spacing) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(AppColor.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: innerSpacing) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(messageFont)
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
        .padding(.vertical, verticalPadding)
        .accessibilityElement(children: .combine)
    }

    private var spacing: CGFloat {
        switch style {
        case .fullScreen: Spacing.lg
        case .compact: Spacing.sm
        }
    }

    private var innerSpacing: CGFloat {
        switch style {
        case .fullScreen: Spacing.sm
        case .compact: Spacing.xs
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .fullScreen: 48
        case .compact: 26
        }
    }

    private var titleFont: Font {
        switch style {
        case .fullScreen: AppFont.title2
        case .compact: AppFont.subheadline
        }
    }

    private var messageFont: Font {
        switch style {
        case .fullScreen: AppFont.subheadline
        case .compact: AppFont.caption
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .fullScreen: Spacing.xxxl
        case .compact: Spacing.md
        }
    }
}

#Preview("With action") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        EmptyStateView(
            icon: "list.clipboard",
            title: "No Protocols Yet",
            message: "Create your first peptide protocol to start tracking your regimen.",
            action: .init(title: "Create Protocol", icon: "plus") {}
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("Without action") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Matches",
            message: "Try a different search term."
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
