import SwiftUI

/// The result the sheet hands back to the caller when the user taps "Apply".
struct StackAdjustmentResult {
    let sourceProtocolId: UUID
    let updatedPeptides: [Peptide]
    let moves: [Move]

    struct Move: Identifiable {
        let id = UUID()
        let peptide: Peptide
        let destination: StackAdjustmentEngine.RelocationOption
    }
}

/// Lets the user edit a stack from a compounding alert. Shows a live `+/-` diff of the proposed
/// changes and, for every peptide they remove, offers a place for it to land — another active stack
/// or a brand-new one — instead of silently dropping it.
struct StackAdjustmentSheet: View {
    let warning: StackRecommendationEngine.Warning
    let candidateProtocols: [PeptideProtocol]
    let allActiveProtocols: [PeptideProtocol]
    let peptideDatabase: [Peptide]
    let hapticEnabled: Bool
    let onApply: (StackAdjustmentResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProtocolId: UUID
    @State private var selectedPeptideIds: Set<UUID>
    /// Per removed peptide: where the user wants to send it. Recomputed when the diff changes.
    @State private var moveChoices: [UUID: StackAdjustmentEngine.RelocationOption] = [:]
    @State private var showingPicker = false

    init(
        warning: StackRecommendationEngine.Warning,
        candidateProtocols: [PeptideProtocol],
        allActiveProtocols: [PeptideProtocol],
        peptideDatabase: [Peptide],
        hapticEnabled: Bool,
        onApply: @escaping (StackAdjustmentResult) -> Void
    ) {
        self.warning = warning
        self.candidateProtocols = candidateProtocols
        self.allActiveProtocols = allActiveProtocols
        self.peptideDatabase = peptideDatabase
        self.hapticEnabled = hapticEnabled
        self.onApply = onApply

        let initial = candidateProtocols.first ?? allActiveProtocols.first
        let initialId = initial?.id ?? UUID()
        _selectedProtocolId = State(initialValue: initialId)
        _selectedPeptideIds = State(initialValue: Set(initial?.peptides.map(\.id) ?? []))
    }

    // MARK: - Derived state

    private var sourceProtocol: PeptideProtocol? {
        allActiveProtocols.first { $0.id == selectedProtocolId }
    }

    private var originalPeptides: [Peptide] {
        sourceProtocol?.peptides ?? []
    }

    private var proposedPeptides: [Peptide] {
        peptideDatabase.filter { selectedPeptideIds.contains($0.id) }
    }

    private var diff: StackAdjustmentEngine.Diff {
        StackAdjustmentEngine.diff(original: originalPeptides, proposed: proposedPeptides)
    }

    private var sideEffectKey: String? {
        StackAdjustmentEngine.sideEffectKey(from: warning.title)
    }

    private var relocations: [StackAdjustmentEngine.Relocation] {
        StackAdjustmentEngine.relocations(
            for: diff.removed,
            sourceProtocolId: selectedProtocolId,
            sideEffectKey: sideEffectKey,
            in: allActiveProtocols
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headerCard
                    if candidateProtocols.count > 1 {
                        stackPickerCard
                    }
                    diffCard
                    editorCard
                    if !relocations.isEmpty {
                        relocationCard
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .safeAreaInset(edge: .bottom) { applyFooter }
            .navigationTitle("Adjust Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: selectedProtocolId) { _, newId in
            if let proto = allActiveProtocols.first(where: { $0.id == newId }) {
                selectedPeptideIds = Set(proto.peptides.map(\.id))
                moveChoices.removeAll()
            }
        }
        .onChange(of: diff.removed.map(\.id)) { _, _ in
            reconcileMoveChoices()
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                Text("ADJUSTING FOR")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text(warning.title)
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(warning.suggestion)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(cardBackground)
    }

    private var stackPickerCard: some View {
        sectionCard(icon: "rectangle.stack.fill", title: "Stack to adjust", tint: AppColor.accentPrimary) {
            VStack(spacing: Spacing.xs) {
                ForEach(candidateProtocols, id: \.id) { proto in
                    Button {
                        if hapticEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        selectedProtocolId = proto.id
                    } label: {
                        stackPickerRow(proto)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stackPickerRow(_ proto: PeptideProtocol) -> some View {
        let isSelected = proto.id == selectedProtocolId
        let affected = Set(warning.peptides)
        let hits = proto.peptides.filter { affected.contains($0.abbreviation) }.count
        return HStack(spacing: Spacing.sm) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(proto.name)
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(proto.peptides.count) peptides · \(hits) flagged")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                    }
            }
        }
    }

    private var diffCard: some View {
        sectionCard(icon: "arrow.triangle.swap", title: "Stack changes", tint: AppColor.accentPrimary) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(diff.summary)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)

                if diff.added.isEmpty && diff.removed.isEmpty {
                    Text("Toggle peptides below or add a new one to preview the change.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.vertical, Spacing.xs)
                } else {
                    if !diff.added.isEmpty {
                        diffRow(symbol: "plus", color: AppColor.success, label: "Adding", peptides: diff.added)
                    }
                    if !diff.removed.isEmpty {
                        diffRow(symbol: "minus", color: AppColor.destructive, label: "Removing", peptides: diff.removed)
                    }
                }
            }
        }
    }

    private func diffRow(symbol: String, color: Color, label: String, peptides: [Peptide]) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 22, height: 22)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(label.uppercased()) (\(peptides.count))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(color)
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(peptides) { peptide in
                        diffChip(peptide: peptide, color: color, removed: symbol == "minus")
                    }
                }
            }
        }
    }

    private func diffChip(peptide: Peptide, color: Color, removed: Bool) -> some View {
        HStack(spacing: 4) {
            Text(peptide.abbreviation)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .strikethrough(removed, color: color.opacity(0.7))
            Text("·")
                .foregroundStyle(color.opacity(0.5))
            Text(peptide.category.displayName)
                .font(AppFont.caption)
                .foregroundStyle(color.opacity(0.85))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(color.opacity(0.14))
                .overlay {
                    Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                }
        }
    }

    private var editorCard: some View {
        sectionCard(icon: "pills.fill", title: "Edit peptides", tint: AppColor.accentPrimary) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Tap to remove. Use \"Add peptide\" to swap one in.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(originalPeptides) { peptide in
                        toggleablePeptideChip(peptide)
                    }
                    ForEach(diff.added) { peptide in
                        toggleablePeptideChip(peptide)
                    }
                }

                Button {
                    if hapticEnabled {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    showingPicker = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add peptide")
                            .font(AppFont.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        Capsule()
                            .strokeBorder(AppColor.accentPrimary.opacity(0.5), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
            }
        }
        .sheet(isPresented: $showingPicker) {
            PeptidePickerSheet(
                selectedPeptides: $selectedPeptideIds,
                allPeptides: peptideDatabase
            )
        }
    }

    private func toggleablePeptideChip(_ peptide: Peptide) -> some View {
        let isIncluded = selectedPeptideIds.contains(peptide.id)
        let color = isIncluded ? AppColor.accentPrimary : AppColor.destructive
        return Button {
            if hapticEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            withAnimation(AppAnimation.springSnappy) {
                if isIncluded {
                    selectedPeptideIds.remove(peptide.id)
                } else {
                    selectedPeptideIds.insert(peptide.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isIncluded ? "checkmark" : "xmark")
                    .font(.system(size: 9, weight: .bold))
                Text(peptide.abbreviation)
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .strikethrough(!isIncluded, color: color.opacity(0.7))
            }
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(color.opacity(isIncluded ? 0.14 : 0.10))
                    .overlay { Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5) }
            }
        }
        .buttonStyle(.plain)
    }

    private var relocationCard: some View {
        sectionCard(icon: "arrow.right.circle.fill", title: "Where should removed peptides go?", tint: AppColor.warning) {
            VStack(spacing: Spacing.md) {
                ForEach(relocations) { relocation in
                    relocationRow(relocation)
                }
            }
        }
    }

    private func relocationRow(_ relocation: StackAdjustmentEngine.Relocation) -> some View {
        let current = moveChoices[relocation.peptide.id] ?? relocation.recommended
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: relocation.peptide.imageSystemName)
                    .font(.system(size: 13))
                    .foregroundStyle(relocation.peptide.category.color)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(relocation.peptide.category.color.opacity(0.15))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(relocation.peptide.abbreviation)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(relocation.peptide.category.displayName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                Spacer()

                Menu {
                    ForEach(relocation.options) { option in
                        Button {
                            if hapticEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            moveChoices[relocation.peptide.id] = option
                        } label: {
                            if let subtitle = option.subtitle {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(option.label)
                                        Text(subtitle).font(.caption2)
                                    }
                                } icon: { Image(systemName: optionIcon(option)) }
                            } else {
                                Label(option.label, systemImage: optionIcon(option))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: optionIcon(current))
                            .font(.system(size: 11, weight: .semibold))
                        Text(current.label)
                            .font(AppFont.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(AppColor.accentPrimary.opacity(0.12))
                            .overlay {
                                Capsule().strokeBorder(AppColor.accentPrimary.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                }
            }
            if let subtitle = current.subtitle {
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.leading, 34)
            }
        }
    }

    private var applyFooter: some View {
        VStack(spacing: Spacing.xs) {
            GlassButton(
                title: diff.hasChanges ? "Apply Changes" : "No Changes",
                icon: diff.hasChanges ? "checkmark" : nil,
                style: diff.hasChanges ? .primary : .ghost,
                isFullWidth: true
            ) {
                guard diff.hasChanges, let source = sourceProtocol else { return }
                if hapticEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                let moves = relocations.map { relocation in
                    StackAdjustmentResult.Move(
                        peptide: relocation.peptide,
                        destination: moveChoices[relocation.peptide.id] ?? relocation.recommended
                    )
                }
                onApply(StackAdjustmentResult(
                    sourceProtocolId: source.id,
                    updatedPeptides: proposedPeptides,
                    moves: moves
                ))
                dismiss()
            }
            .disabled(!diff.hasChanges || proposedPeptides.isEmpty)
            .opacity((!diff.hasChanges || proposedPeptides.isEmpty) ? 0.5 : 1)

            if proposedPeptides.isEmpty {
                Text("Keep at least one peptide in the stack.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.destructive)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.md)
        .background {
            LinearGradient(
                colors: [Color.clear, AppColor.background.opacity(0.85), AppColor.background],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Helpers

    private func reconcileMoveChoices() {
        let removedIds = Set(diff.removed.map(\.id))
        moveChoices = moveChoices.filter { removedIds.contains($0.key) }
    }

    private func optionIcon(_ option: StackAdjustmentEngine.RelocationOption) -> String {
        switch option {
        case .discard: return "trash"
        case .moveTo: return "arrow.right.circle"
        case .createStack: return "plus.rectangle.on.rectangle"
        }
    }

    @ViewBuilder
    private func sectionCard<Inner: View>(
        icon: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.textSecondary)
            }
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.55))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous)
                    .fill(AppColor.cardOverlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius + 4, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
    }
}

// PeptidePickerSheet lives in Components/Adjustment/.
