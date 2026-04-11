import SwiftUI

struct DoseLogRow: View {
    let entry: ProtocolEntry

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(entry.completed ? AppColor.accentPrimary : AppColor.textTertiary)

            Image(systemName: entry.peptide.imageSystemName)
                .font(.system(size: 12))
                .foregroundStyle(entry.peptide.category.color)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(entry.peptide.category.color.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.peptide.abbreviation)
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.textPrimary)

                Text(entry.dose)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Text(entry.date.formatted(.dateTime.hour().minute()))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.vertical, Spacing.xs)
    }
}
