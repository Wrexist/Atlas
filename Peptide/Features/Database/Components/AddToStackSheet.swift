import SwiftUI

struct AddToStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                    .sectionAppear(index: index)
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
                        let delayMs: UInt64 = reduceMotion ? 0 : 250
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(delayMs))
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
                    Button("Done") { dismiss() }
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
                        .font(AppFont.scaled(18))
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
        GlassCard {
            VStack(spacing: Spacing.md) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColor.textTertiary)
                Text("No stacks yet")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textSecondary)
                Text("Create your first stack to add \(peptide.abbreviation).")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
    }

    @ViewBuilder
    private func stackRow(_ proto: PeptideProtocol) -> some View {
        let alreadyIn = proto.peptides.contains(where: { $0.id == peptide.id })
        let justAdded = justAddedTo == proto.id

        Button {
            guard !alreadyIn else { return }
            let success = dataStore.addPeptide(peptide, toProtocolId: proto.id)
            if success {
                withAnimation(AppAnimation.springSnappy) {
                    justAddedTo = proto.id
                }
                let delayMs: UInt64 = reduceMotion ? 0 : 600
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    dismiss()
                }
            }
        } label: {
            stackRowBody(proto, alreadyIn: alreadyIn, justAdded: justAdded)
        }
        .buttonStyle(StackPickerPressStyle())
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
                        Text("\(proto.peptides.count) peptide\(proto.peptides.count == 1 ? "" : "s")")
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
                .font(AppFont.scaled(14, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
        }
        .liquidGlass(.circle)
    }

    @ViewBuilder
    private func statusBadge(alreadyIn: Bool, justAdded: Bool, status: ProtocolStatus) -> some View {
        if justAdded {
            badgeText("Added", color: AppColor.accentLight, bg: AppColor.accentLight.opacity(0.2))
        } else if alreadyIn {
            badgeText("In stack", color: AppColor.accentPrimary, bg: AppColor.accentPrimary.opacity(0.15))
        } else if status == .paused {
            badgeText("Paused", color: AppColor.warning, bg: AppColor.warning.opacity(0.15))
        }
    }

    private func badgeText(_ text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(AppFont.scaled(10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background { Capsule().fill(bg) }
    }
}

private struct StackPickerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(AppAnimation.springSnappy, value: configuration.isPressed)
    }
}

#Preview {
    AddToStackSheet(peptide: MockPeptides.bpc157, onCreateNew: {})
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
