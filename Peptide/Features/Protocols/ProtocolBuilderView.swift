import SwiftUI

struct ProtocolBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    var preselectedPeptide: Peptide?
    var editingProtocol: PeptideProtocol?

    @State private var name = ""
    @State private var selectedPeptides: Set<UUID> = []
    @State private var cycleLengthWeeks = 8
    @State private var timesPerDay = 1
    @State private var notes = ""
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var currentStep = 0
    @State private var peptideOverrides: [UUID: ProtocolSchedule] = [:]
    @State private var editingOverridePeptide: Peptide?

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let totalSteps = 2

    private var isEditing: Bool { editingProtocol != nil }

    private var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedPeptides.isEmpty
    }

    private var canCreate: Bool {
        canProceed && !selectedDays.isEmpty
    }

    private var orderedSelectedPeptides: [Peptide] {
        dataStore.peptideDatabase.filter { selectedPeptides.contains($0.id) }
    }

    private var defaultSchedule: ProtocolSchedule {
        ProtocolSchedule(
            daysOfWeek: selectedDays.sorted(),
            timesPerDay: timesPerDay,
            preferredTimes: generateDefaultTimes(count: timesPerDay)
        )
    }

    /// Non-persisted protocol used to drive the live preview share-card render.
    private var previewProtocol: PeptideProtocol {
        PeptideProtocol(
            id: editingProtocol?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "New Stack" : name,
            peptides: orderedSelectedPeptides,
            schedule: defaultSchedule,
            peptideSchedules: peptideOverrides,
            cycleLengthWeeks: cycleLengthWeeks,
            startDate: editingProtocol?.startDate ?? Date(),
            status: .active,
            notes: notes,
            authorName: editingProtocol?.authorName ?? attributionName,
            authorHandle: editingProtocol?.authorHandle,
            forkedFromStackId: editingProtocol?.forkedFromStackId,
            createdAt: editingProtocol?.createdAt ?? Date()
        )
    }

    private var attributionName: String? {
        if let display = AuthService.shared.userDisplayName,
           !display.trimmingCharacters(in: .whitespaces).isEmpty {
            return display
        }
        let profileName = dataStore.profile.name.trimmingCharacters(in: .whitespaces)
        return profileName.isEmpty ? nil : profileName
    }

    private var inlineWarnings: [StackRecommendationEngine.Warning] {
        StackRecommendationEngine.warnings(
            for: orderedSelectedPeptides,
            activeProtocols: dataStore.activeProtocols
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    StepIndicator(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.md)

                    ZStack {
                        if currentStep == 0 {
                            detailsStep
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            scheduleStep
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Protocol" : "New Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep == 0 {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(AppColor.textSecondary)
                    } else {
                        Button {
                            withAnimation(AppAnimation.springSnappy) {
                                currentStep = 0
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                            }
                            .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == 0 {
                        Button("Next") {
                            withAnimation(AppAnimation.springSnappy) {
                                currentStep = 1
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(canProceed ? AppColor.accentPrimary : AppColor.textTertiary)
                        .disabled(!canProceed)
                    }
                }
            }
            .onAppear {
                if let peptide = preselectedPeptide {
                    selectedPeptides.insert(peptide.id)
                }
                if let proto = editingProtocol {
                    name = proto.name
                    selectedPeptides = Set(proto.peptides.map(\.id))
                    cycleLengthWeeks = proto.cycleLengthWeeks
                    timesPerDay = proto.schedule.timesPerDay
                    notes = proto.notes
                    selectedDays = Set(proto.schedule.daysOfWeek)
                    peptideOverrides = proto.peptideSchedules
                }
            }
            .onChange(of: selectedPeptides) { _, newValue in
                // Drop overrides for peptides that have been deselected.
                peptideOverrides = peptideOverrides.filter { newValue.contains($0.key) }
            }
            .sheet(item: $editingOverridePeptide) { peptide in
                PeptideScheduleSheet(
                    peptide: peptide,
                    defaultSchedule: defaultSchedule,
                    initialOverride: peptideOverrides[peptide.id]
                ) { updated in
                    if let updated {
                        peptideOverrides[peptide.id] = updated
                    } else {
                        peptideOverrides.removeValue(forKey: peptide.id)
                    }
                }
            }
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if !isEditing {
                    NavigationLink(value: StackLibraryRoute()) {
                        browseLibraryRow
                    }
                    .buttonStyle(.plain)
                    .sectionAppear(index: 0)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Protocol Name", systemImage: "pencil")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        TextField("e.g., Recovery Stack", text: $name)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .tint(AppColor.accentPrimary)
                            .padding(Spacing.md)
                            .background {
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .fill(AppColor.surfaceElevated)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                    }
                            }
                    }
                }
                .sectionAppear(index: 1)

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Select Peptides", systemImage: "flask.fill")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        PeptideSelector(
                            selectedPeptides: $selectedPeptides,
                            allPeptides: dataStore.peptideDatabase,
                            onAddCustomPeptide: { dataStore.addCustomPeptide($0) }
                        )
                    }
                }
                .sectionAppear(index: 2)

                let warnings = inlineWarnings
                if !warnings.isEmpty {
                    warningsCard(warnings)
                        .sectionAppear(index: 3)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
    }

    private var browseLibraryRow: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Start from a community stack")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Browse research-backed templates")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.glassTint)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }
        }
    }

    private func warningsCard(_ warnings: [StackRecommendationEngine.Warning]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Heads up", systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.warning)

                ForEach(warnings.prefix(3)) { warning in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: warning.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.warning)
                            .frame(width: 18, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(warning.title)
                                .font(AppFont.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(warning.detail)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                livePreviewCard
                    .sectionAppear(index: 0)

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Default Schedule", systemImage: "calendar")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            if !peptideOverrides.isEmpty {
                                Text("\(peptideOverrides.count) custom")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.accentPrimary)
                            }
                        }

                        Text("Applies to peptides that don't have a custom schedule.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)

                        schedulePresetChips

                        ScheduleEditor(
                            selectedDays: $selectedDays,
                            timesPerDay: $timesPerDay,
                            cycleLengthWeeks: $cycleLengthWeeks,
                            dayNames: dayNames
                        )
                    }
                }
                .sectionAppear(index: 1)

                if !orderedSelectedPeptides.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Per-Peptide Schedule", systemImage: "slider.horizontal.3")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            Text("Tap a peptide to give it its own days and frequency.")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)

                            VStack(spacing: Spacing.xs) {
                                ForEach(Array(orderedSelectedPeptides.enumerated()), id: \.element.id) { index, peptide in
                                    PeptideScheduleRow(
                                        peptide: peptide,
                                        schedule: peptideOverrides[peptide.id] ?? defaultSchedule,
                                        isCustom: peptideOverrides[peptide.id] != nil
                                    ) {
                                        editingOverridePeptide = peptide
                                    }

                                    if index < orderedSelectedPeptides.count - 1 {
                                        Divider().foregroundStyle(AppColor.glassBorder)
                                    }
                                }
                            }
                        }
                    }
                    .sectionAppear(index: 2)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("Notes", systemImage: "note.text")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        TextField("Optional notes...", text: $notes, axis: .vertical)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .tint(AppColor.accentPrimary)
                            .lineLimit(3...6)
                            .padding(Spacing.md)
                            .background {
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .fill(AppColor.surfaceElevated)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                    }
                            }
                    }
                }
                .sectionAppear(index: 3)

                GlassButton(
                    title: isEditing ? "Save Changes" : "Create Protocol",
                    icon: isEditing ? "checkmark.circle.fill" : "plus.circle.fill",
                    style: .primary,
                    isFullWidth: true
                ) {
                    isEditing ? saveProtocol() : createProtocol()
                }
                .opacity(canCreate ? 1.0 : 0.5)
                .disabled(!canCreate)
                .sectionAppear(index: 4)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
    }

    private var livePreviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("Preview", systemImage: "eye.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("1080 × 1350")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColor.textTertiary)
                }

                CycleCardView(proto: previewProtocol, showsQR: false)
                    .frame(
                        width: ShareCardRenderer.canvasSize.width,
                        height: ShareCardRenderer.canvasSize.height
                    )
                    .scaleEffect(0.26, anchor: .topLeading)
                    .frame(
                        width: ShareCardRenderer.canvasSize.width * 0.26,
                        height: ShareCardRenderer.canvasSize.height * 0.26
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var schedulePresetChips: some View {
        HStack(spacing: Spacing.sm) {
            schedulePresetChip(label: "Daily", days: [1, 2, 3, 4, 5, 6, 7], times: 1)
            schedulePresetChip(label: "5-on / 2-off", days: [1, 2, 3, 4, 5], times: 1)
            schedulePresetChip(label: "Every other", days: [1, 3, 5, 7], times: 1)
            Spacer(minLength: 0)
        }
    }

    private func schedulePresetChip(label: String, days: [Int], times: Int) -> some View {
        let daySet = Set(days)
        let isSelected = daySet == selectedDays && times == timesPerDay
        return Button {
            selectedDays = daySet
            timesPerDay = times
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected ? AppColor.glassTint : AppColor.cardOverlay)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func createProtocol() {
        let peptides = orderedSelectedPeptides
        guard !peptides.isEmpty else { return }

        let newProtocol = PeptideProtocol(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            peptides: peptides,
            schedule: defaultSchedule,
            peptideSchedules: peptideOverrides,
            cycleLengthWeeks: cycleLengthWeeks,
            startDate: Date(),
            status: .active,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            authorName: attributionName,
            createdAt: Date()
        )

        dataStore.addProtocol(newProtocol)
        dismiss()
    }

    private func saveProtocol() {
        guard let proto = editingProtocol else { return }
        let peptides = orderedSelectedPeptides
        guard !peptides.isEmpty else { return }

        let times: [String]
        if timesPerDay == proto.schedule.timesPerDay {
            times = proto.schedule.preferredTimes
        } else {
            times = generateDefaultTimes(count: timesPerDay)
        }

        dataStore.updateProtocol(
            id: proto.id,
            name: name.trimmingCharacters(in: .whitespaces),
            peptides: peptides,
            schedule: ProtocolSchedule(
                daysOfWeek: selectedDays.sorted(),
                timesPerDay: timesPerDay,
                preferredTimes: times
            ),
            peptideSchedules: peptideOverrides,
            cycleLengthWeeks: cycleLengthWeeks,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }

    private func generateDefaultTimes(count: Int) -> [String] {
        (1...count).map { index in
            let hour24 = min(8 + (index - 1) * (12 / max(count, 1)), 23)
            let hour12 = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24)
            let period = hour24 >= 12 ? "PM" : "AM"
            return "\(hour12):00 \(period)"
        }
    }
}

private struct PeptideScheduleRow: View {
    let peptide: Peptide
    let schedule: ProtocolSchedule
    let isCustom: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: peptide.imageSystemName)
                    .font(.system(size: 14))
                    .foregroundStyle(peptide.category.color)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(peptide.category.color.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(peptide.abbreviation)
                            .font(AppFont.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColor.textPrimary)
                        if isCustom {
                            Text("CUSTOM")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppColor.accentPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule()
                                        .fill(AppColor.accentPrimary.opacity(0.15))
                                }
                        }
                    }
                    HStack(spacing: 4) {
                        Text(schedule.summary)
                            .font(AppFont.caption)
                            .foregroundStyle(isCustom ? AppColor.accentLight : AppColor.textTertiary)
                        if let dose = schedule.customDose, !dose.isEmpty {
                            Text("·")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                            Text(dose)
                                .font(AppFont.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.accentLight)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? AppColor.accentPrimary : AppColor.surfaceElevated)
                    .frame(height: 4)
                    .overlay {
                        Capsule()
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                    .animation(AppAnimation.springSmooth, value: currentStep)
            }
        }
    }
}

#Preview {
    ProtocolBuilderView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
