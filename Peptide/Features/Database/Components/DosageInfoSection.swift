import SwiftUI

struct DosageInfoSection: View {
    let peptide: Peptide

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Dosage Information", systemImage: "syringe.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

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
        }
    }
}

private struct DosageRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 20)

                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(AppColor.textPrimary)
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
