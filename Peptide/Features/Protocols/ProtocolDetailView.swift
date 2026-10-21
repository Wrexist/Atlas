import SwiftUI

struct ProtocolDetailView: View {
    let protocol_: PeptideProtocol
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showShareCard = false
    @State private var showPaywall = false
    @State private var schedulingPeptide: Peptide?

    private var liveProtocol: PeptideProtocol {
        dataStore.protocols.first { $0.id == protocol_.id } ?? protocol_
    }

    private var recentEntries: [ProtocolEntry] {
        Array(dataStore.entriesFor(protocolId: protocol_.id).prefix(10))
    }

    /// Adherence over the last 14 days (rounded percent). `entriesFor`
    /// uses `startOfDay(of: today - days)` as the cutoff, so passing 13
    /// covers the same inclusive window (13 prior days + today).
    private var adherencePercent: Int? {
        let entries = dataStore.entriesFor(protocolId: protocol_.id, days: 13)
        guard let ratio = liveProtocol.adherence(entries: entries, days: 14) else { return nil }
        return Int((ratio * 100).rounded())
    }

    private var customScheduleCount: Int {
        liveProtocol.peptideSchedules.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                GlassCard(tinted: true) {
                    VStack(spacing: Spacing.lg) {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(liveProtocol.name)
                                    .font(AppFont.title)
                                    .foregroundStyle(AppColor.textPrimary)

                                Text("\(liveProtocol.cycleLengthWeeks)-week cycle")
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()

                            StatusBadge(status: liveProtocol.status)
                        }

                        if liveProtocol.status == .active {
                            CycleProgressBar(protocol_: liveProtocol)

                            // Surface the cycle-phase card only
                            // when the protocol uses wash-out
                            // cycles. Single-cycle protocols are
                            // already covered by `CycleProgressBar`
                            // above — duplicating would clutter.
                            if liveProtocol.washoutWeeks > 0 {
                                CyclePhaseCard(status: CyclePhaseEngine.status(for: liveProtocol))
                            }
                        }

                        // Stats row. Once a user rolls into their
                        // second cycle (8-on-4-off, repeated), the
                        // bare "Week 2" loses the cycle context;
                        // prefix with "C2 ·" so they read both
                        // (audit Library P2.14).
                        HStack(spacing: Spacing.lg) {
                            let weekLabel: String = liveProtocol.cycleNumber > 1
                                ? String(localized: "C\(liveProtocol.cycleNumber) · W\(liveProtocol.weekNumber)", comment: "Protocol detail — abbreviation for 'Cycle N · Week M' when the user is on their second or later cycle")
                                : String(localized: "Week \(liveProtocol.weekNumber)", comment: "Protocol detail — first-cycle week label")
                            MiniStat(value: weekLabel, label: "Current")
                            MiniStat(value: "\(liveProtocol.daysRemaining)", label: "Days Left")
                            if let adherencePercent {
                                MiniStat(value: "\(adherencePercent)%", label: "Adherence")
                            } else {
                                MiniStat(value: "\(liveProtocol.peptides.count)", label: "Peptides")
                            }
                        }
                    }
                }
                .sectionAppear(index: 0)

                // Status actions. Side by side when they fit, stacked at
                // accessibility text sizes rather than truncating.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.md) { protocolActions }
                    VStack(spacing: Spacing.sm) { protocolActions }
                }
                .sectionAppear(index: 1)

                // Peptides in protocol — tap row to edit schedule, tap info icon to view details.
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Label("Peptides", systemImage: "flask.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            if customScheduleCount > 0 {
                                Badge("\(customScheduleCount) custom")
                            }
                            Spacer()
                            Text("Tap to edit schedule")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        let peptides = liveProtocol.peptides
                        ForEach(Array(peptides.enumerated()), id: \.element.id) { index, peptide in
                            peptideRow(peptide, in: liveProtocol)
                            if index < peptides.count - 1 {
                                Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
                            }
                        }
                    }
                }
                .sectionAppear(index: 2)

                // Schedule
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Schedule", systemImage: "calendar")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        scheduleDetailRow(
                            label: liveProtocol.schedule.isInterval ? "Cadence" : "Days",
                            value: liveProtocol.schedule.daysDescription
                        )

                        Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)

                        scheduleDetailRow(label: "Times/Day", value: "\(liveProtocol.schedule.timesPerDay)x")

                        // Interval protocols imported from the library carry
                        // no preferred times; an empty row reads as broken.
                        if !liveProtocol.schedule.preferredTimes.isEmpty {
                            Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)

                            scheduleDetailRow(
                                label: "Preferred",
                                value: liveProtocol.schedule.preferredTimes.joined(separator: ", ")
                            )
                        }

                        Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)

                        scheduleDetailRow(
                            label: "Cycle",
                            value: "\(formattedDate(liveProtocol.startDate)) – \(formattedDate(liveProtocol.endDate))"
                        )
                    }
                }
                .sectionAppear(index: 3)

                // Static protocol-creation notes (entered at
                // builder time). Surfaces only when populated.
                if !liveProtocol.notes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("About this protocol", systemImage: "note.text")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            Text(liveProtocol.notes)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                    .sectionAppear(index: 4)
                }

                // Per-day journal entries — qualitative companion
                // to the dose / cycle data above.
                GlassCard {
                    ProtocolNotesTimeline(
                        protocolID: liveProtocol.id,
                        protocolName: liveProtocol.name,
                        notes: dataStore.protocolNotes(for: liveProtocol.id),
                        onSave: { dataStore.saveProtocolNote($0) },
                        onDelete: { dataStore.deleteProtocolNote(id: $0) }
                    )
                }
                .sectionAppear(index: 5)

                // Recent logs
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Recent Logs", systemImage: "list.bullet")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            if !recentEntries.isEmpty {
                                Text("\(recentEntries.filter(\.completed).count)/\(recentEntries.count) done")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }

                        if recentEntries.isEmpty {
                            EmptyStateView(
                                icon: "tray",
                                title: "No entries yet",
                                message: "Logged doses for this protocol will appear here.",
                                style: .compact
                            )
                        } else {
                            ForEach(Array(recentEntries.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    Haptics.selection()
                                    AppAnimation.with(AppAnimation.springSnappy) {
                                        dataStore.toggleEntry(entry.id)
                                    }
                                } label: {
                                    DoseLogRow(entry: entry)
                                }
                                .buttonStyle(.plain)

                                if index < recentEntries.count - 1 {
                                    Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
                .sectionAppear(index: 6)

                // Delete button
                GlassButton(title: "Delete Protocol", icon: "trash", style: .destructive, isFullWidth: true) {
                    Haptics.warning()
                    showDeleteConfirmation = true
                }
                .sectionAppear(index: 7)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share cycle card")
            }
        }
        .alert("Delete Protocol", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dataStore.deleteProtocol(id: protocol_.id)
                Haptics.success()
            }
        } message: {
            Text("This will permanently delete \"\(liveProtocol.name)\" and all its logged entries.")
        }
        .confirmationDialog(
            "Complete \(liveProtocol.name)?",
            isPresented: $showCompleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Complete Protocol") { setStatus(.completed) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Completed and stops scheduling doses. You can restart it later.")
        }
        .onChange(of: dataStore.protocols.contains(where: { $0.id == protocol_.id })) { _, exists in
            if !exists { dismiss() }
        }
        .sheet(isPresented: $showEditSheet) {
            ProtocolBuilderView(editingProtocol: liveProtocol)
                .liquidGlassPresentation()
        }
        .sheet(isPresented: $showShareCard) {
            ShareCardSheet(subject: .singleProtocol(liveProtocol))
                .liquidGlassPresentation()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .protocolLimit)
                .liquidGlassPresentation()
        }
        .sheet(item: $schedulingPeptide) { peptide in
            PeptideScheduleSheet(
                peptide: peptide,
                defaultSchedule: liveProtocol.schedule,
                initialOverride: liveProtocol.peptideSchedules[peptide.id]
            ) { updated in
                dataStore.setPeptideSchedule(
                    protocolId: liveProtocol.id,
                    peptideId: peptide.id,
                    schedule: updated
                )
            }
            .liquidGlassPresentation()
        }
    }

    @ViewBuilder
    private func peptideRow(_ peptide: Peptide, in proto: PeptideProtocol) -> some View {
        let schedule = proto.schedule(for: peptide.id)
        let isCustom = proto.hasCustomSchedule(for: peptide.id)

        // Sibling buttons (not nested) so SwiftUI routes taps cleanly:
        // most of the row edits the schedule; the trailing info icon navigates to peptide details.
        HStack(spacing: Spacing.md) {
            Button {
                schedulingPeptide = peptide
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: peptide.imageSystemName)
                        .font(AppFont.scaled(16))
                        .foregroundStyle(peptide.category.color)
                        .frame(width: 32, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                                .fill(peptide.category.color.opacity(0.15))
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Text(peptide.abbreviation)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            if isCustom {
                                Badge("Custom")
                            }
                        }
                        HStack(spacing: Spacing.xs) {
                            if let custom = schedule.customDose, !custom.isEmpty {
                                Text(custom)
                                    .font(AppFont.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppColor.accentLight)
                                Text("(\(peptide.dosageRange))")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                                    .lineLimit(1)
                            } else {
                                Text(peptide.dosageRange)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                    }

                    Spacer(minLength: Spacing.sm)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(schedule.compactDaysDescription)
                            .font(AppFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(isCustom ? AppColor.accentLight : AppColor.textPrimary)
                            .lineLimit(1)
                        Text("\(schedule.timesPerDay)x daily")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink(value: peptide) {
                Image(systemName: "info.circle")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(peptide.name) details")
        }
    }

    @ViewBuilder
    private func scheduleDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: Spacing.md)
            Text(value)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    @ViewBuilder
    private var protocolActions: some View {
        switch liveProtocol.status {
        case .active:
            GlassButton(title: "Pause", icon: "pause.fill", style: .secondary) {
                setStatus(.paused)
            }
            GlassButton(title: "Complete", icon: "checkmark", style: .primary) {
                showCompleteConfirmation = true
            }
        case .paused:
            GlassButton(title: "Resume", icon: "play.fill", style: .primary) {
                setStatus(.active)
            }
            GlassButton(title: "Complete", icon: "checkmark", style: .secondary) {
                showCompleteConfirmation = true
            }
        case .completed:
            GlassButton(title: "Restart", icon: "arrow.counterclockwise", style: .primary) {
                // A finished cycle needs a fresh start date, not just a
                // status flip — otherwise it reads 100% done and
                // auto-completes again on the next launch.
                applyStatusChange(.active) {
                    dataStore.restartProtocol(id: protocol_.id)
                }
            }
        }
    }

    private func setStatus(_ status: ProtocolStatus) {
        applyStatusChange(status) {
            dataStore.updateProtocolStatus(id: protocol_.id, to: status)
        }
    }

    /// Runs `change` and plays its haptic, or presents the paywall when
    /// the free-tier cap blocked an activation.
    private func applyStatusChange(_ status: ProtocolStatus, _ change: () -> Bool) {
        guard AppAnimation.with(AppAnimation.springSnappy, change) else {
            if status == .active { showPaywall = true }
            return
        }
        if status == .completed {
            Haptics.success()
        } else {
            Haptics.impact(.light)
        }
    }
}

private struct MiniStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(AppFont.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(AppColor.accentLight)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        ProtocolDetailView(protocol_: MockProtocols.recoveryStack)
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
