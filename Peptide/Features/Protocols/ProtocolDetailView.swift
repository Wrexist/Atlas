import SwiftUI

struct ProtocolDetailView: View {
    let protocol_: PeptideProtocol
    @State private var entries: [ProtocolEntry] = []

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
                .sectionAppear(index: 1)

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
                .sectionAppear(index: 2)

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
                    .sectionAppear(index: 3)
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
                                DoseLogRow(entry: entry)
                                if entry != entries.prefix(10).last {
                                    Divider().foregroundStyle(AppColor.glassBorder)
                                }
                            }
                        }
                    }
                }
                .sectionAppear(index: 4)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .background(AppColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            entries = MockEntries.generateEntries(for: protocol_, days: 14)
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
    .preferredColorScheme(.dark)
}
