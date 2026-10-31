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

            IconTile(entry.peptide.imageSystemName, size: 24)

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

    /// When the dose was actually taken, falling back to its slot. The
    /// Recent Logs list spans two weeks, so anything before today carries
    /// its date too.
    private var time: String {
        let moment = entry.actualTime ?? entry.date
        return Calendar.current.isDateInToday(moment)
            ? moment.formatted(.dateTime.hour().minute())
            : moment.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var accessibilityLabel: String {
        let status = entry.completed ? String(localized: "Completed") : String(localized: "Pending")
        let dose = entry.dose.isEmpty ? time : String(localized: "\(entry.dose) at \(time)")
        return "\(entry.peptide.name), \(dose), \(status)"
    }
}
