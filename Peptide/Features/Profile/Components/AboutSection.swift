import SwiftUI

struct AboutSection: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("About", systemImage: "info.circle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: Spacing.md) {
                    AboutRow(title: "Version", value: "1.0.0")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    AboutRow(title: "Build", value: "1")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    AboutLinkRow(title: "Privacy Policy", icon: "lock.shield.fill")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    AboutLinkRow(title: "Terms of Service", icon: "doc.text.fill")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    AboutLinkRow(title: "Support", icon: "questionmark.circle.fill")
                }

                HStack {
                    Spacer()
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "atom")
                            .font(.system(size: 24))
                            .foregroundStyle(AppColor.accentPrimary)

                        Text("Peptide AI")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    Spacer()
                }
                .padding(.top, Spacing.sm)
            }
        }
    }
}

private struct AboutRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}

private struct AboutLinkRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 20)

            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AboutSection()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
