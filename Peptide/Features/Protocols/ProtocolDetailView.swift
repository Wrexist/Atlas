import SwiftUI

struct ProtocolDetailView: View {
    let protocol_: PeptideProtocol
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    private var entries: [ProtocolEntry] {
        dataStore.entriesFor(protocolId: protocol_.id)
    }

    private var currentProtocol: PeptideProtocol? {
        dataStore.protocols.first { $0.id == protocol_.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                GlassCard(tinted: true) {
                    VStack(spacing: Spacing.lg) {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(protocol_.name)
                                    .font(AppFont.title)
                                    .foregroundStyle(AppColor.textPrimary)

                                Text("\(protocol_.cycleLengthWeeks)-week cycle")
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()

                            if let status = currentProtocol?.status {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: status.iconName)
                                    Text(status.displayName)
                                }
                                .font(AppFont.caption)
                                .foregroundStyle(status.color)
                            }
                        }

                        if protocol_.status == .active {
                            CycleProgressBar(protocol_: protocol_)
                        }

                        // Stats row
                        HStack(spacing: Spacing.lg) {
                            MiniStat(value: "Week \(protocol_.weekNumber)", label: "Current")
                            MiniStat(value: "\(protocol_.daysRemaining)", label: "Days Left")
                            MiniStat(value: "\(protocol_.peptides.count)", label: "Peptides")
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

                        ForEach(protocol_.peptides) { peptide in
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

                            if peptide != protocol_.peptides.last {
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
                            Text(protocol_.schedule.daysDescription)
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        Divider().foregroundStyle(AppColor.glassBorder)

                        HStack {
                            Text("Times/Day")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Text("\(protocol_.schedule.timesPerDay)x")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        Divider().foregroundStyle(AppColor.glassBorder)

                        HStack {
                            Text("Preferred")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Text(protocol_.schedule.preferredTimes.joined(separator: ", "))
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                        }
                    }
                }
                .sectionAppear(index: 3)

                // Notes
                if !protocol_.notes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Notes", systemImage: "note.text")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            Text(protocol_.notes)
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

                        if entries.isEmpty {
                            Text("No entries yet")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textTertiary)
                        } else {
                            ForEach(entries.prefix(10)) { entry in
                                Button {
                                    dataStore.toggleEntry(entry.id)
                                } label: {
                                    DoseLogRow(entry: entry)
                                }
                                .buttonStyle(.plain)

                                if entry != entries.prefix(10).last {
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
                dismiss()
            }
        } message: {
            Text("This will permanently delete \"\(protocol_.name)\" and all its logged entries.")
        }
    }

    @ViewBuilder
    private var protocolActions: some View {
        if let current = currentProtocol {
            HStack(spacing: Spacing.md) {
                switch current.status {
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
