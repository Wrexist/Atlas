import SwiftUI

struct DoseLogRow: View {
    let entry: ProtocolEntry

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(16))
                .foregroundStyle(entry.completed ? AppColor.accentPrimary : AppColor.textTertiary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: entry.completed)

            Image(systemName: entry.peptide.imageSystemName)
                .font(AppFont.scaled(11))
                .foregroundStyle(entry.peptide.category.color)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                        .fill(entry.peptide.category.color.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.peptide.abbreviation)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)

                Text(entry.dose)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Text(time)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// When the dose was actually taken, falling back to its slot.
    private var time: String {
        (entry.actualTime ?? entry.date).formatted(.dateTime.hour().minute())
    }

    private var accessibilityLabel: String {
        let status = entry.completed ? "completed" : "pending"
        let dose = entry.dose.isEmpty ? time : "\(entry.dose) at \(time)"
        return "\(entry.peptide.name), \(dose), \(status)"
    }
}
