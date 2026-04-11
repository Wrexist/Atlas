import SwiftUI

struct TodayScheduleCard: View {
    let entries: [ProtocolEntry]
    let onToggle: (ProtocolEntry) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)

                    Text("Today's Schedule")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    Spacer()

                    Text("\(entries.count) doses")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                VStack(spacing: Spacing.sm) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ScheduleRow(entry: entry, onToggle: { onToggle(entry) })
                            .staggeredAppear(index: index)
                    }
                }
            }
        }
    }
}

private struct ScheduleRow: View {
    let entry: ProtocolEntry
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(entry.completed ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }

            Image(systemName: entry.peptide.imageSystemName)
                .font(.system(size: 14))
                .foregroundStyle(entry.peptide.category.color)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(entry.peptide.category.color.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.peptide.abbreviation)
                    .font(AppFont.headline)
                    .foregroundStyle(
                        entry.completed ? AppColor.textSecondary : AppColor.textPrimary
                    )
                    .strikethrough(entry.completed, color: AppColor.textTertiary)

                Text(entry.dose)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Text(entry.date.formatted(.dateTime.hour().minute()))
                .font(AppFont.subheadline)
                .foregroundStyle(
                    entry.completed ? AppColor.textTertiary : AppColor.accentLight
                )
        }
        .padding(.vertical, Spacing.xs)
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TodayScheduleCard(entries: MockEntries.todayEntries()) { _ in }
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
