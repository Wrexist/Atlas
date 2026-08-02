import SwiftUI

/// Renders the smart daily plan produced by `DailyScheduleEngine`. Lists each
/// time-of-day window with its ordered doses, validated co-injection partners,
/// and timing conflicts the user should know about.
struct DailyPlanCard: View {
    let plan: DailyScheduleEngine.DailyPlan
    var onTapDose: ((ProtocolEntry) -> Void)?

    /// Collapsed by default so the card stays scannable even when the
    /// user has 4+ time-of-day slots. The first slot shows in full
    /// (the next thing they need to do) and the rest reveal via the
    /// "Show all" button.
    @State private var isExpanded = false

    /// Slots rendered now. When collapsed we keep just the first
    /// time-of-day window so the user sees the most-imminent doses
    /// without scrolling past everything below.
    private var visibleSlots: [DailyScheduleEngine.ScheduledSlot] {
        isExpanded ? plan.slots : Array(plan.slots.prefix(1))
    }

    private var hiddenSlotCount: Int {
        max(0, plan.slots.count - visibleSlots.count)
    }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if !plan.hasAny {
                    emptyState
                } else {
                    ForEach(visibleSlots) { scheduledSlot in
                        slotSection(scheduledSlot)
                    }

                    if hiddenSlotCount > 0 || (plan.slots.count > 1 && isExpanded) {
                        expandToggle
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expandToggle: some View {
        Button {
            withAnimation(.smooth(duration: 0.28)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(AppFont.scaled(11, weight: .bold))
                Text(isExpanded
                     ? "Show less"
                     : "Show \(hiddenSlotCount) more time slot\(hiddenSlotCount == 1 ? "" : "s")")
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(AppColor.accentLight)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "wand.and.stars")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                Text("Smart Daily Plan")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if plan.combinationCount > 0 {
                    countBadge(
                        icon: "link",
                        count: plan.combinationCount,
                        color: AppColor.accentPrimary
                    )
                }
                if plan.conflictCount > 0 {
                    countBadge(
                        icon: "exclamationmark.triangle.fill",
                        count: plan.conflictCount,
                        color: AppColor.warning
                    )
                }
            }

            Text(plan.headline)
                .font(AppFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(AppColor.textPrimary)

            Text(plan.summary)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func countBadge(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.badgeSmall)
            Text("\(count)")
                .font(AppFont.badge)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background { Capsule().fill(color.opacity(0.15)) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "calendar.badge.exclamationmark",
            title: "No doses today",
            message: "Add a protocol to see your organized plan.",
            style: .compact
        )
    }

    // MARK: - Slot section

    private func slotSection(_ scheduled: DailyScheduleEngine.ScheduledSlot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            slotHeader(scheduled.slot, count: scheduled.doses.count)
            VStack(spacing: Spacing.sm) {
                ForEach(scheduled.doses) { dose in
                    DailyPlanDoseRow(dose: dose, onTap: onTapDose)
                }
            }
            .padding(.leading, Spacing.xs)
        }
    }

    private func slotHeader(_ slot: DailyScheduleEngine.DaySlot, count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: slot.iconName)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 22, height: 22)
                .background { Circle().fill(AppColor.accentPrimary.opacity(0.15)) }
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(slot.caption)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            Text("\(count)")
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background { Capsule().fill(AppColor.surfaceElevated) }
        }
    }
}

// MARK: - Dose row

private struct DailyPlanDoseRow: View {
    let dose: DailyScheduleEngine.PlannedDose
    var onTap: ((ProtocolEntry) -> Void)?

    var body: some View {
        Button {
            onTap?(dose.entry)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                topRow
                if !dose.timingNote.isEmpty {
                    Text(dose.timingNote)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                ForEach(dose.combinations, id: \.self) { combo in
                    combinationChip(combo)
                }
                ForEach(dose.conflicts, id: \.self) { conflict in
                    conflictChip(conflict)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceElevated.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var topRow: some View {
        HStack(spacing: Spacing.sm) {
            orderBadge

            Image(systemName: dose.entry.peptide.imageSystemName)
                .font(AppFont.scaled(13))
                .foregroundStyle(dose.entry.peptide.category.color)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                        .fill(dose.entry.peptide.category.color.opacity(0.15))
                }
                .symbolEffect(.bounce, value: dose.entry.completed)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(dose.entry.peptide.abbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            dose.entry.completed ? AppColor.textSecondary : AppColor.textPrimary
                        )
                        .strikethrough(dose.entry.completed, color: AppColor.textTertiary)

                    if dose.mustBeFasted {
                        fastedFlag
                    }
                }
                Text(dose.entry.dose)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Text(dose.entry.date.formatted(.dateTime.hour().minute()))
                .font(AppFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(
                    dose.entry.completed ? AppColor.textTertiary : AppColor.accentLight
                )
        }
    }

    private var orderBadge: some View {
        Text("\(dose.order)")
            .font(AppFont.scaled(11, weight: .bold))
            .foregroundStyle(AppColor.accentLight)
            .frame(width: 20, height: 20)
            .background {
                Circle().fill(AppColor.accentPrimary.opacity(0.2))
            }
            .overlay {
                Circle().strokeBorder(AppColor.accentPrimary.opacity(0.4), lineWidth: 0.5)
            }
    }

    private var fastedFlag: some View {
        Text("FASTED")
            .font(AppFont.scaled(8, weight: .bold))
            .foregroundStyle(AppColor.warning)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background { Capsule().fill(AppColor.warning.opacity(0.15)) }
    }

    private func combinationChip(_ combo: DailyScheduleEngine.CombinationHint) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "link")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("Co-inject with \(combo.withAbbreviation) — \(combo.stackName)")
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                Text(combo.synergy)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.10))
        }
    }

    private func conflictChip(_ conflict: DailyScheduleEngine.ConflictHint) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: conflict.severity == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(severityColor(conflict.severity))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(conflict.title)
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(severityColor(conflict.severity))
                Text(conflict.detail)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                .fill(severityColor(conflict.severity).opacity(0.10))
        }
    }

    private func severityColor(_ severity: DailyScheduleEngine.ConflictHint.Severity) -> Color {
        switch severity {
        case .info:    return AppColor.accentLight
        case .caution: return AppColor.warning
        case .danger:  return AppColor.destructive
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        DailyPlanCard(plan: DailyPlanCardPreviewSamples.populated)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

private enum DailyPlanCardPreviewSamples {
    static var populated: DailyScheduleEngine.DailyPlan {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        let bed = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: Date()) ?? Date()
        let proto = MockProtocols.all.first
        let entries: [ProtocolEntry] = [
            ProtocolEntry(
                id: UUID(),
                protocolId: proto?.id ?? UUID(),
                peptide: MockPeptides.bpc157,
                date: morning,
                dose: "500 mcg",
                notes: "",
                completed: false
            ),
            ProtocolEntry(
                id: UUID(),
                protocolId: proto?.id ?? UUID(),
                peptide: MockPeptides.cjc1295,
                date: bed,
                dose: "100 mcg",
                notes: "",
                completed: false
            ),
            ProtocolEntry(
                id: UUID(),
                protocolId: proto?.id ?? UUID(),
                peptide: MockPeptides.tb500,
                date: morning,
                dose: "5 mg",
                notes: "",
                completed: false
            ),
        ]
        return DailyScheduleEngine.plan(for: entries)
    }
}
