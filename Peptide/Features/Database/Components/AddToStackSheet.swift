import SwiftUI

struct AddToStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the "Added" state holds before the sheet closes, so the
    /// confirmation registers.
    private static let addedConfirmationHold: Duration = .milliseconds(600)

    let peptide: Peptide
    var onCreateNew: () -> Void

    @State private var justAddedTo: UUID?

    private var availableProtocols: [PeptideProtocol] {
        dataStore.activeProtocols + dataStore.pausedProtocols
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    header

                    if availableProtocols.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: Spacing.md) {
                            ForEach(Array(availableProtocols.enumerated()), id: \.element.id) { index, proto in
                                stackRow(proto)
                                    .staggeredAppear(index: index)
                            }
                        }
                    }

                    GlassButton(
                        title: "Create New Stack",
                        icon: "plus.circle.fill",
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        dismiss()
                        // Wait out the dismissal: presenting the builder
                        // before this sheet is gone gets silently dropped.
                        Task { @MainActor in
                            try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                            onCreateNew()
                        }
                    }
                    .padding(.top, Spacing.sm)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Add to Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.accentLight)
                }
            }
        }
    }

    private var header: some View {
        GlassCard(tinted: true) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(peptide.category.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: peptide.imageSystemName)
                        .font(AppFont.scaled(16))
                        .foregroundStyle(peptide.category.color)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(peptide.abbreviation)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Pick a stack to add this peptide to")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "square.stack.3d.up.slash",
            title: "No stacks yet",
            message: "Create your first stack to add \(peptide.abbreviation).",
            style: .compact
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stackRow(_ proto: PeptideProtocol) -> some View {
        let alreadyIn = proto.peptides.contains(where: { $0.id == peptide.id })
        let justAdded = justAddedTo == proto.id

        Button {
            guard !alreadyIn else { return }
            let success = dataStore.addPeptide(peptide, toProtocolId: proto.id)
            if success {
                Haptics.success()
                AppAnimation.with(AppAnimation.springSnappy) {
                    justAddedTo = proto.id
                }
                Task { @MainActor in
                    if !reduceMotion {
                        try? await Task.sleep(for: Self.addedConfirmationHold)
                    }
                    dismiss()
                }
            }
        } label: {
            stackRowBody(proto, alreadyIn: alreadyIn, justAdded: justAdded)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(alreadyIn)
    }

    private func stackRowBody(_ proto: PeptideProtocol, alreadyIn: Bool, justAdded: Bool) -> some View {
        GlassCard(tinted: alreadyIn || justAdded) {
            HStack(spacing: Spacing.md) {
                statusGlyph(alreadyIn: alreadyIn, justAdded: justAdded)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(proto.name)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text("^[\(proto.peptides.count) peptide](inflect: true)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)

                        Text("·")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)

                        Text(proto.schedule.daysDescription)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                statusBadge(alreadyIn: alreadyIn, justAdded: justAdded, status: proto.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func statusGlyph(alreadyIn: Bool, justAdded: Bool) -> some View {
        ZStack {
            Circle()
                .fill(AppColor.accentPrimary.opacity(alreadyIn || justAdded ? 0.25 : 0.1))
                .frame(width: 36, height: 36)

            Image(systemName: (alreadyIn || justAdded) ? "checkmark" : "plus")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: justAdded)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func statusBadge(alreadyIn: Bool, justAdded: Bool, status: ProtocolStatus) -> some View {
        if justAdded {
            Badge("Added", icon: "checkmark")
        } else if alreadyIn {
            Badge("In stack")
        } else if status == .paused {
            Badge("Paused", tint: AppColor.warning)
        }
    }
}

#Preview {
    AddToStackSheet(peptide: MockPeptides.bpc157, onCreateNew: {})
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
