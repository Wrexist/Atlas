import SwiftUI

struct ProtocolDetailView: View {
    let protocol_: PeptideProtocol
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showShareCard = false
    @State private var schedulingPeptide: Peptide?

    private var liveProtocol: PeptideProtocol {
        dataStore.protocols.first { $0.id == protocol_.id } ?? protocol_
    }

    private var recentEntries: [ProtocolEntry] {
        Array(dataStore.entriesFor(protocolId: protocol_.id).prefix(10))
    }

    /// All logged entries (past 14 days) for this protocol — used for adherence stats.
    /// `entriesFor` uses `startOfDay(of: today - days)` as the cutoff, so passing 13
    /// gives an inclusive 14-day window (13 prior days + today).
    private var allRecentEntries: [ProtocolEntry] {
        dataStore.entriesFor(protocolId: protocol_.id, days: 13)
    }

    /// Adherence: completed entries / total entries (rounded percent). Returns nil if no entries.
    private var adherencePercent: Int? {
        let entries = allRecentEntries
        guard !entries.isEmpty else { return nil }
        let completed = entries.filter(\.completed).count
        return Int((Double(completed) / Double(entries.count) * 100).rounded())
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

                            HStack(spacing: Spacing.xs) {
                                Image(systemName: liveProtocol.status.iconName)
                                Text(liveProtocol.status.displayName)
                            }
                            .font(AppFont.caption)
                            .foregroundStyle(liveProtocol.status.color)
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
                            let weekLabel = liveProtocol.cycleNumber > 1
                                ? "C\(liveProtocol.cycleNumber) · W\(liveProtocol.weekNumber)"
                                : "Week \(liveProtocol.weekNumber)"
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

                // Protocol Actions
                HStack(spacing: Spacing.md) {
                    GlassButton(title: "Edit", icon: "pencil", style: .secondary) {
                        showEditSheet = true
                    }
                    protocolActions
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
                                Text("\(customScheduleCount) custom")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AppColor.accentPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background {
                                        Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                                    }
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
                                Divider().foregroundStyle(AppColor.glassBorder)
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

                        Divider().foregroundStyle(AppColor.glassBorder)

                        scheduleDetailRow(label: "Times/Day", value: "\(liveProtocol.schedule.timesPerDay)x")

                        Divider().foregroundStyle(AppColor.glassBorder)

                        scheduleDetailRow(
                            label: "Preferred",
                            value: liveProtocol.schedule.preferredTimes.joined(separator: ", ")
                        )

                        Divider().foregroundStyle(AppColor.glassBorder)

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
                            Label("Notes", systemImage: "note.text")
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
                .sectionAppear(index: 4)

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
                                    dataStore.toggleEntry(entry.id)
                                } label: {
                                    DoseLogRow(entry: entry)
                                }
                                .buttonStyle(.plain)

                                if index < recentEntries.count - 1 {
                                    Divider().foregroundStyle(AppColor.glassBorder)
                                }
                            }
                        }
                    }
                }
                .sectionAppear(index: 5)

                // Delete button
                GlassButton(title: "Delete Protocol", icon: "trash", style: .destructive, isFullWidth: true) {
                    showDeleteConfirmation = true
                }
                .sectionAppear(index: 6)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            }
        } message: {
            Text("This will permanently delete \"\(liveProtocol.name)\" and all its logged entries.")
        }
        .navigationDestination(for: Peptide.self) { peptide in
            PeptideDetailView(peptide: peptide)
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
                        .font(.system(size: 16))
                        .foregroundStyle(peptide.category.color)
                        .frame(width: 32, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                                .fill(peptide.category.color.opacity(0.15))
                        }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Text(peptide.abbreviation)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            if isCustom {
                                Text("CUSTOM")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AppColor.accentPrimary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background {
                                        Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                                    }
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))
    }

    @ViewBuilder
    private var protocolActions: some View {
        HStack(spacing: Spacing.md) {
            switch liveProtocol.status {
            case .active:
                GlassButton(title: "Pause", icon: "pause.fill", style: .secondary) {
                    dataStore.updateProtocolStatus(id: protocol_.id, to: .paused)
                }
                GlassButton(title: "Complete", icon: "checkmark", style: .primary) {
                    dataStore.updateProtocolStatus(id: protocol_.id, to: .completed)
                }
            case .paused:
                GlassButton(title: "Resume", icon: "play.fill", style: .primary) {
                    dataStore.updateProtocolStatus(id: protocol_.id, to: .active)
                }
                GlassButton(title: "Complete", icon: "checkmark", style: .secondary) {
                    dataStore.updateProtocolStatus(id: protocol_.id, to: .completed)
                }
            case .completed:
                GlassButton(title: "Restart", icon: "arrow.counterclockwise", style: .primary) {
                    dataStore.updateProtocolStatus(id: protocol_.id, to: .active)
                }
            }
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
