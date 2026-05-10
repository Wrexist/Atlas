import SwiftUI

struct TodayScheduleCard: View {
    let entries: [ProtocolEntry]
    let onToggle: (ProtocolEntry) -> Void
    var onTap: ((ProtocolEntry) -> Void)?

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
                    if entries.isEmpty {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(AppColor.textTertiary)

                            Text("No doses scheduled today")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                    } else {
                        ForEach(entries) { entry in
                            ScheduleRow(
                                entry: entry,
                                onToggle: { onToggle(entry) },
                                onTap: { onTap?(entry) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct ScheduleRow: View {
    let entry: ProtocolEntry
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Circle button = quick toggle
            Button(action: onToggle) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(entry.completed ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityLabel(entry.completed ? "Mark dose incomplete" : "Mark dose complete")

            // Tapping the row = open detailed logging sheet. The press
            // feedback now matches the rest of the app via ScalePressStyle
            // instead of the dead .plain style.
            Button(action: onTap) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: entry.peptide.imageSystemName)
                        .font(.system(size: 14))
                        .foregroundStyle(entry.peptide.category.color)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                                .fill(entry.peptide.category.color.opacity(0.15))
                        }
                        .symbolEffect(.bounce, value: entry.completed)

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
                .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint("Opens dose logging.")
        }
        .padding(.vertical, Spacing.xs)
    }

    private var rowAccessibilityLabel: String {
        let time = entry.date.formatted(.dateTime.hour().minute())
        let status = entry.completed ? "completed" : "pending"
        return "\(entry.peptide.name), \(entry.dose) at \(time), \(status)"
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TodayScheduleCard(entries: []) { _ in }
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
