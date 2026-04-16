import SwiftUI

struct DosageInfoSection: View {
    let peptide: Peptide

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "syringe.fill")
                        .foregroundStyle(peptide.category.color)
                        .accessibilityHidden(true)
                    Text("Dosage Information")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }

                VStack(spacing: Spacing.md) {
                    DosageRow(label: "Dosage Range", value: peptide.dosageRange, icon: "scalemass.fill")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    DosageRow(label: "Frequency", value: peptide.frequency, icon: "clock.fill")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    DosageRow(label: "Half-Life", value: peptide.halfLife, icon: "hourglass")
                    Divider().foregroundStyle(AppColor.glassBorder)
                    DosageRow(label: "Administration", value: peptide.adminRoute, icon: "cross.vial.fill")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DosageRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 20)

                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .layoutPriority(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        DosageInfoSection(peptide: MockPeptides.bpc157)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
