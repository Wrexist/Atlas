import SwiftUI

struct ProtocolDetailView: View {
    let protocol_: PeptideProtocol
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    private var liveProtocol: PeptideProtocol {
        dataStore.protocols.first { $0.id == protocol_.id } ?? protocol_
    }

    private var recentEntries: [ProtocolEntry] {
        Array(dataStore.entriesFor(protocolId: protocol_.id).prefix(10))
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
                        }

                        // Stats row
                        HStack(spacing: Spacing.lg) {
                            MiniStat(value: "Week \(liveProtocol.weekNumber)", label: "Current")
                            MiniStat(value: "\(liveProtocol.daysRemaining)", label: "Days Left")
                            MiniStat(value: "\(liveProtocol.peptides.count)", label: "Peptides")
                        }
                    }
                }
                .sectionAppear(index: 0)

                // Protocol Actions
                protocolActions
                    .sectionAppear(index: 1)

                // Peptides in protocol
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Peptides", systemImage: "flask.fill")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        let peptides = liveProtocol.peptides
                        ForEach(Array(peptides.enumerated()), id: \.element.id) { index, peptide in
                            HStack(spacing: Spacing.md) {
                                Image(systemName: peptide.imageSystemName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(peptide.category.color)
                                    .frame(width: 32, height: 32)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(peptide.category.color.opacity(0.15))
                                    }

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(peptide.abbreviation)
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text(peptide.dosageRange)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }

                                Spacer()

                                Text(peptide.frequency)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                            }

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

                        HStack {
                            Text("Days")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Text(liveProtocol.schedule.daysDescription)
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        Divider().foregroundStyle(AppColor.glassBorder)

                        HStack {
                            Text("Times/Day")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Text("\(liveProtocol.schedule.timesPerDay)x")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        Divider().foregroundStyle(AppColor.glassBorder)

                        HStack {
                            Text("Preferred")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Text(liveProtocol.schedule.preferredTimes.joined(separator: ", "))
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                        }
                    }
                }
                .sectionAppear(index: 3)

                // Notes
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

                // Recent logs
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Recent Logs", systemImage: "list.bullet")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        if recentEntries.isEmpty {
                            Text("No entries yet")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, Spacing.lg)
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
        .alert("Delete Protocol", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dataStore.deleteProtocol(id: protocol_.id)
            }
        } message: {
            Text("This will permanently delete \"\(liveProtocol.name)\" and all its logged entries.")
        }
        .onChange(of: dataStore.protocols.contains(where: { $0.id == protocol_.id })) { _, exists in
            if !exists { dismiss() }
        }
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
    .environment(DataStore())
    .preferredColorScheme(.dark)
}
