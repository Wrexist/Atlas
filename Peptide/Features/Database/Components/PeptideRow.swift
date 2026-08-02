import SwiftUI

struct PeptideRow: View {
    let peptide: Peptide

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(peptide.category.color.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: peptide.imageSystemName)
                    .font(AppFont.scaled(20))
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
                .font(AppFont.scaled(12, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .glassCard(cornerRadius: Spacing.smallCornerRadius, padding: Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(peptide.abbreviation), \(peptide.name)")
        .accessibilityValue(peptide.category.displayName)
        .accessibilityHint("Opens peptide details")
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
