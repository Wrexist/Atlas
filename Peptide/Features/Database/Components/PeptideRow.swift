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
            .accessibilityHidden(true)

            // The coloured tile already names the category (and VoiceOver
            // reads it as the value), so the row stays two lines tall.
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(peptide.abbreviation)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Text(peptide.name)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        // A flat inset surface, not a live glass effect: 200+ of these sit
        // in one lazy list, and per-row glass made scrolling heavy and busy.
        .insetRowBackground(cornerRadius: Spacing.smallCornerRadius)
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
