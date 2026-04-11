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
                    ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
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
                                    Text("•")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textTertiary)
                                    Text("\(link.year)")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textTertiary)
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColor.textTertiary)
                        }

                        if index < links.count - 1 {
                            Divider().foregroundStyle(AppColor.glassBorder)
                        }
                    }
                }
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
