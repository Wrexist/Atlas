import SwiftUI

struct PeptideRow: View {
    let peptide: Peptide

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(peptide.category.color.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: peptide.imageSystemName)
                    .font(.system(size: 20))
                    .foregroundStyle(peptide.category.color)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(peptide.abbreviation)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Text(peptide.name)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)

                PeptideCategoryBadge(category: peptide.category)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .glassCard(cornerRadius: Spacing.smallCornerRadius, padding: Spacing.md)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            PeptideRow(peptide: MockPeptides.bpc157)
            PeptideRow(peptide: MockPeptides.semax)
        }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
