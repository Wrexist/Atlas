import SwiftUI

struct ResearchLinksSection: View {
    let links: [ResearchLink]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Research", systemImage: "doc.text.magnifyingglass")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: Spacing.md) {
                    ForEach(links) { link in
                        researchRow(link: link)

                        if link.id != links.last?.id {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func researchRow(link: ResearchLink) -> some View {
        if !link.url.isEmpty, let url = URL(string: link.url) {
            Link(destination: url) {
                researchRowContent(link: link, tappable: true)
            }
        } else {
            researchRowContent(link: link, tappable: false)
        }
    }

    private func researchRowContent(link: ResearchLink, tappable: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "doc.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(link.title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    Text(link.source)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                    Text("\u{2022}")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                    Text("\(link.year)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                if !link.pmid.isEmpty {
                    Text("PMID: \(link.pmid)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentPrimary.opacity(0.8))
                }
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tappable ? AppColor.accentPrimary : AppColor.textTertiary)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ResearchLinksSection(links: MockPeptides.bpc157.researchLinks)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
