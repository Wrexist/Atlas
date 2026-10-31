import SwiftUI

struct ResearchLinksSection: View {
    let links: [ResearchLink]
    var categoryColor: Color = AppColor.accentPrimary

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(categoryColor)
                        .accessibilityHidden(true)
                    Text("Research")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }

                VStack(spacing: Spacing.md) {
                    ForEach(links) { link in
                        researchRow(link: link)

                        if link.id != links.last?.id {
                            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func researchRow(link: ResearchLink) -> some View {
        if let url = link.resolvedURL {
            Link(destination: url) {
                researchRowContent(link: link, tappable: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens in Safari")
        } else {
            researchRowContent(link: link, tappable: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func researchRowContent(link: ResearchLink, tappable: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "doc.fill")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(link.title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    Text(link.source)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                    Text("\u{2022}")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                        .accessibilityHidden(true)
                    Text(verbatim: String(link.year))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                if !link.pmid.isEmpty {
                    Text("PMID: \(link.pmid)")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Spacer()

            if tappable {
                Image(systemName: "arrow.up.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .accessibilityHidden(true)
            }
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
