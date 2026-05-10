import SwiftUI

/// Shared empty-state surface used by the primary lists (Protocols, Peptides,
/// per-protocol dose log) so they all read with the same visual rhythm
/// instead of three slightly-different inline VStacks. Optional `action`
/// renders a primary `GlassButton` underneath the copy.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: Action? = nil

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
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(AppColor.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AppFont.subheadline)
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
        .padding(.vertical, Spacing.xxxl)
        .accessibilityElement(children: .combine)
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
