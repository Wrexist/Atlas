import SwiftUI

/// The one home for today's doses on Today. Renders the plan produced by
/// `DailyScheduleEngine`: each time-of-day window with its doses, validated
/// co-injection partners and timing conflicts. Every row carries its
/// taken/pending state — the leading check marks it taken in one tap, the
/// rest of the row opens the full logging sheet.
struct DailyPlanCard: View {
    let plan: DailyScheduleEngine.DailyPlan
    /// False when every protocol is paused or completed — only then does
    /// the empty state ask the user to add one.
    let hasActiveProtocols: Bool
    var onTapDose: ((ProtocolEntry) -> Void)?
    /// Marks a dose taken (or not). Nil hides the check, e.g. in previews.
    var onToggleDose: ((ProtocolEntry) -> Void)?
    /// Route to the protocol list. Optional so the CTA only renders where
    /// the host can actually service it — the empty-state copy asks the
    /// user to add a protocol, and it should not ask without offering.
    var onAddProtocol: (() -> Void)?

    /// A browsed past day: no callbacks, so the card is a record of what
    /// was taken rather than a plan to act on.
    private var isReadOnly: Bool { onToggleDose == nil && onTapDose == nil }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if !plan.hasAny {
                    emptyState
                } else {
                    header

                    ForEach(plan.slots) { scheduledSlot in
                        slotSection(scheduledSlot)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    /// The section header above already says "Today's doses", so the
    /// card opens on the plan's own headline rather than a second title.
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(isReadOnly ? plan.recordHeadline : plan.headline)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
                if plan.conflictCount > 0 {
                    countBadge(
                        icon: "exclamationmark.triangle.fill",
                        count: plan.conflictCount,
                        color: AppColor.warning,
                        accessibilityLabel: String(localized: "\(plan.conflictCount) timing notes")
                    )
                }
            }

            Text(plan.summary)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)

            doseProgress
        }
    }

    private var allDoses: [DailyScheduleEngine.PlannedDose] {
        plan.slots.flatMap(\.doses)
    }

    private var takenCount: Int {
        allDoses.filter(\.entry.completed).count
    }

    /// How far through the day's doses the user is — the plan's headline
    /// names the next one, this shows the distance left.
    private var doseProgress: some View {
        HStack(spacing: Spacing.sm) {
            GlassProgressBar(
                progress: allDoses.isEmpty ? 0 : Double(takenCount) / Double(allDoses.count)
            )
            Text("\(takenCount)/\(allDoses.count) taken")
                .font(AppFont.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(takenCount == allDoses.count ? AppColor.success : AppColor.textSecondary)
        }
        .padding(.top, Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(takenCount) of \(allDoses.count) doses taken"))
    }

    private func countBadge(icon: String, count: Int, color: Color, accessibilityLabel: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.badgeSmall)
            Text("\(count)")
                .font(AppFont.badge)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background { Capsule().fill(color.opacity(0.15)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Empty state

    private var addProtocolAction: EmptyStateView.Action? {
        guard let onAddProtocol else { return nil }
        return EmptyStateView.Action(title: "Add a protocol",
                                     icon: "plus.circle.fill",
                                     perform: onAddProtocol)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isReadOnly {
            EmptyStateView(
                icon: "calendar",
                title: "Nothing was scheduled",
                message: "No doses were due that day.",
                style: .compact
            )
        } else if hasActiveProtocols {
            EmptyStateView(
                icon: "calendar",
                title: "Nothing scheduled today",
                message: "Rest day — no doses are due today.",
                style: .compact
            )
        } else {
            EmptyStateView(
                icon: "calendar.badge.exclamationmark",
                title: "No doses today",
                message: "Add a protocol to see your organized plan.",
                action: addProtocolAction,
                style: .compact
            )
        }
    }

    // MARK: - Slot section

    /// Every window, flat on the card: a one-line label over its rows, no
    /// inner panels, so the whole day reads at one level.
    private func slotSection(_ scheduled: DailyScheduleEngine.ScheduledSlot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            slotHeader(scheduled.slot)
            ForEach(scheduled.doses) { dose in
                DailyPlanDoseRow(dose: dose, onTap: onTapDose, onToggle: onToggleDose)
            }
        }
    }

    private func slotHeader(_ slot: DailyScheduleEngine.DaySlot) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: slot.iconName)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)
            Text(slot.title)
                .font(AppFont.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)
            Text(slot.caption)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One tap to mark the dose taken without opening the sheet.
    private func toggleButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: dose.entry.completed ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(20))
                .foregroundStyle(dose.entry.completed ? AppColor.success : AppColor.textTertiary)
                .contentTransition(.symbolEffect(.replace))
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(
            dose.entry.completed
                ? Text("Mark \(dose.entry.peptide.abbreviation) not taken")
                : Text("Mark \(dose.entry.peptide.abbreviation) taken")
        )
    }

    /// A button only when the host can open dose logging; a past day's row
    /// is a plain record, so it neither sinks on press nor announces an
    /// action that never runs.
    @ViewBuilder
    private var detailsButton: some View {
        if let onTap {
            Button {
                onTap(dose.entry)
            } label: {
                details
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            // One VoiceOver stop per dose instead of icon, name, flag,
            // dose and time read separately.
            .accessibilityElement(children: .combine)
            .accessibilityValue(dose.entry.completed ? "Taken" : "Pending")
            .accessibilityHint("Opens dose logging")
        } else {
            details
                .accessibilityElement(children: .combine)
                .accessibilityValue(dose.entry.completed ? "Taken" : "Pending")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            topRow
            if !dose.timingNote.isEmpty {
                Text(dose.timingNote)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            ForEach(dose.conflicts, id: \.self) { conflict in
                conflictChip(conflict)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var topRow: some View {
        HStack(spacing: Spacing.sm) {
            IconTile(dose.entry.peptide.imageSystemName, size: 26)
                .symbolEffect(.bounce, value: dose.entry.completed)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Spacer()

            Text(dose.entry.date.formatted(.dateTime.hour().minute()))
                .font(AppFont.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(
                    dose.entry.completed ? AppColor.textTertiary : AppColor.accentLight
                )
                .fixedSize()
        }
    }

    private var fastedFlag: some View {
        Text("Fasted")
            .textCase(.uppercase)
            .font(AppFont.badgeSmall)
            .foregroundStyle(AppColor.warning)
            .fixedSize()
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background { Capsule().fill(AppColor.warning.opacity(0.15)) }
    }

    private func conflictChip(_ conflict: DailyScheduleEngine.ConflictHint) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: conflict.severity == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(severityColor(conflict.severity))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(conflict.title)
                    .font(AppFont.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(severityColor(conflict.severity))
                // Unclipped: the logging sheet doesn't repeat interaction
                // reasons, so this is the only place they can be read.
                Text(conflict.detail)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
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
        DailyPlanCard(plan: DailyPlanCardPreviewSamples.populated, hasActiveProtocols: true)
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
