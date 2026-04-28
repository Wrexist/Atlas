import SwiftUI

struct GlassNavBar: View {
    let title: String
    var subtitle: String?
    var leadingAction: (() -> Void)?
    var trailingIcon: String?
    var trailingAccessibilityLabel: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let leadingAction {
                GlassIconButton(icon: "chevron.left", accessibilityLabel: "Back") {
                    leadingAction()
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer()

            if let trailingIcon, let trailingAction {
                GlassIconButton(
                    icon: trailingIcon,
                    accessibilityLabel: trailingAccessibilityLabel ?? "Action"
                ) {
                    trailingAction()
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack {
            GlassNavBar(
                title: "Peptide Database",
                subtitle: "55+ compounds",
                trailingIcon: "line.3.horizontal.decrease.circle",
                trailingAccessibilityLabel: "Filter peptides"
            ) {}
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
