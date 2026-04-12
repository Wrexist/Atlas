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
                    AboutRow(title: "Peptide Database", value: "\(MockPeptides.all.count) peptides")
                }

                HStack {
                    Spacer()
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "atom")
                            .font(.system(size: 24))
                            .foregroundStyle(AppColor.accentPrimary)

                        Text("PeptideX")
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

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AboutSection()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
