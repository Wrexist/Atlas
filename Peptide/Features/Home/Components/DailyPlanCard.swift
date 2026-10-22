import SwiftUI

/// The one home for today's doses on Today. Renders the plan produced by
/// `DailyScheduleEngine`: each time-of-day window with its doses, validated
/// co-injection partners and timing conflicts. Every row carries its
/// taken/pending state — the leading check marks it taken in one tap, the
/// rest of the row opens the full logging sheet.
struct DailyPlanCard: View {
    let plan: DailyScheduleEngine.DailyPlan
    var onTapDose: ((ProtocolEntry) -> Void)?
    /// Marks a dose taken (or not). Nil hides the check, e.g. in previews.
    var onToggleDose: ((ProtocolEntry) -> Void)?
    /// Route to the protocol list. Optional so the CTA only renders where
    /// the host can actually service it — the empty-state copy asks the
    /// user to add a protocol, and it should not ask without offering.
    var onAddProtocol: (() -> Void)?

    /// Collapsed by default so the card stays scannable even when the
    /// user has 4+ time-of-day slots. The current slot shows in full
    /// (the next thing they need to do) and the rest reveal via the
    /// "Show more" button.
    @State private var isExpanded = false

    /// Slots rendered now. When collapsed we keep the first window that
    /// still has a dose to take — or the last one once everything is
    /// logged — so the open doses are never hidden behind the toggle.
    private var visibleSlots: [DailyScheduleEngine.ScheduledSlot] {
        guard !isExpanded else { return plan.slots }
        let current = plan.slots.first { slot in
            slot.doses.contains { !$0.entry.completed }
        } ?? plan.slots.last
        return current.map { [$0] } ?? []
    }

    private var hiddenSlotCount: Int {
        max(0, plan.slots.count - visibleSlots.count)
    }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if !plan.hasAny {
                    emptyState
                } else {
                    header

                    ForEach(visibleSlots) { scheduledSlot in
                        slotSection(scheduledSlot)
                            .transition(.move(edge: .top).combined(with: .opacity))
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
            AppAnimation.with(AppAnimation.settle) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chevron.down")
                    .font(AppFont.scaled(11, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
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
        .buttonStyle(ScalePressStyle())
    }

    // MARK: - Header

    /// The section header above already says "Today's doses", so the
    /// card opens on the plan's own headline rather than a second title.
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(plan.headline)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
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

    private var addProtocolAction: EmptyStateView.Action? {
        guard let onAddProtocol else { return nil }
        return EmptyStateView.Action(title: "Add a protocol",
                                     icon: "plus.circle.fill",
                                     perform: onAddProtocol)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "calendar.badge.exclamationmark",
            title: "No doses today",
            message: "Add a protocol to see your organized plan.",
            action: addProtocolAction,
            style: .compact
        )
    }

    // MARK: - Slot section

    private func slotSection(_ scheduled: DailyScheduleEngine.ScheduledSlot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            slotHeader(scheduled.slot, count: scheduled.doses.count)
            VStack(spacing: Spacing.sm) {
                ForEach(scheduled.doses) { dose in
                    DailyPlanDoseRow(dose: dose, onTap: onTapDose, onToggle: onToggleDose)
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
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background { Capsule().fill(AppColor.surfaceElevated) }
        }
    }
}

// MARK: - Dose row

private struct DailyPlanDoseRow: View {
    let dose: DailyScheduleEngine.PlannedDose
    var onTap: ((ProtocolEntry) -> Void)?
    var onToggle: ((ProtocolEntry) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if let onToggle {
                toggleButton { onToggle(dose.entry) }
            }
            detailsButton
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

    /// One tap to mark the dose taken without opening the sheet.
    private func toggleButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: dose.entry.completed ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(20))
                .foregroundStyle(dose.entry.completed ? AppColor.accentPrimary : AppColor.textTertiary)
                .contentTransition(.symbolEffect(.replace))
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(dose.entry.completed ? "Mark dose incomplete" : "Mark dose complete")
    }

    private var detailsButton: some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        // One VoiceOver stop per dose instead of icon, name, flag,
        // dose and time read separately.
        .accessibilityElement(children: .combine)
        .accessibilityValue(dose.entry.completed ? "Taken" : "Pending")
        .accessibilityHint("Opens dose logging")
    }

    private var topRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: dose.entry.peptide.imageSystemName)
                .font(AppFont.scaled(13))
                .foregroundStyle(dose.entry.peptide.category.color)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                        .fill(dose.entry.peptide.category.color.opacity(0.15))
                }
                .symbolEffect(.bounce, value: dose.entry.completed)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xs) {
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
                if !dose.entry.dose.isEmpty {
                    Text(dose.entry.dose)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Spacer()

            Text(dose.entry.date.formatted(.dateTime.hour().minute()))
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    dose.entry.completed ? AppColor.textTertiary : AppColor.accentLight
                )
        }
    }

    private var fastedFlag: some View {
        Text("Fasted")
            .textCase(.uppercase)
            .font(AppFont.badgeSmall)
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
