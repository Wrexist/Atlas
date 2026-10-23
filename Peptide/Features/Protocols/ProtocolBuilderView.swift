import SwiftUI

struct ProtocolBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    var preselectedPeptide: Peptide?
    var editingProtocol: PeptideProtocol?

    @State private var name = ""
    @State private var selectedPeptides: Set<UUID> = []
    @State private var cycleLengthWeeks = 8
    /// Optional wash-out duration. `0` keeps the legacy single-cycle
    /// behaviour. The toggle in the form exposes the field once
    /// the user opts into cycling so most users (one-and-done
    /// protocols) never see the complexity.
    @State private var washoutWeeks = 0
    @State private var timesPerDay = 1
    @State private var notes = ""
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var cadenceMode: ScheduleCadenceMode = .weekly
    @State private var intervalDays: Int = 3
    @State private var intervalAnchor: Date = Date()
    @State private var preferredTimes: [String] = ["8:00 AM"]
    @State private var currentStep = 0
    @State private var navigationPath = NavigationPath()
    @State private var peptideOverrides: [UUID: ProtocolSchedule] = [:]
    @State private var editingOverridePeptide: Peptide?
    @State private var appendTargetProtocolId: UUID?
    @State private var isShowingAppendPicker = false
    /// Stable identity for the live-preview `PeptideProtocol`. Computed once
    /// per builder lifecycle so SwiftUI doesn't see a fresh id on every
    /// body invocation.
    @State private var previewID = UUID()
    /// `onAppear` re-fires on every pop back from the pushed library
    /// screens; without this guard edit mode re-hydrated from the stored
    /// protocol and wiped whatever the user had changed.
    @State private var didHydrate = false
    /// Rebuilt (debounced) only when the preview protocol changes, so the
    /// full-canvas share card isn't re-modelled on every keystroke.
    @State private var previewModel: CycleCardModel?
    /// Fixed "now" for the preview so its identity (and the task keyed on
    /// it) doesn't change on every body pass.
    @State private var previewDate = Date()
    /// The form as it stood after hydration, so Cancel and the swipe-down
    /// only cost the user a prompt once they've actually entered something.
    @State private var initialForm: FormSnapshot?
    @State private var isConfirmingDiscard = false
    /// Recomputed when the selection changes, not on every keystroke in
    /// the name field.
    @State private var inlineWarnings: [StackRecommendationEngine.Warning] = []

    private let dayNames = ScheduleEditor.isoWeekdayNames
    private let totalSteps = 2

    private var isEditing: Bool { editingProtocol != nil }

    private struct FormSnapshot: Equatable {
        let name: String
        let selectedPeptides: Set<UUID>
        let cycleLengthWeeks: Int
        let washoutWeeks: Int
        let timesPerDay: Int
        let notes: String
        let selectedDays: Set<Int>
        let cadenceMode: ScheduleCadenceMode
        let intervalDays: Int
        let intervalAnchor: Date
        let preferredTimes: [String]
        let peptideOverrides: [UUID: ProtocolSchedule]
        let appendTargetProtocolId: UUID?
    }

    private var currentForm: FormSnapshot {
        FormSnapshot(
            name: name,
            selectedPeptides: selectedPeptides,
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            timesPerDay: timesPerDay,
            notes: notes,
            selectedDays: selectedDays,
            cadenceMode: cadenceMode,
            intervalDays: intervalDays,
            intervalAnchor: intervalAnchor,
            preferredTimes: preferredTimes,
            peptideOverrides: peptideOverrides,
            appendTargetProtocolId: appendTargetProtocolId
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let initialForm else { return false }
        return currentForm != initialForm
    }

    private var builderTitle: String {
        if isEditing { return String(localized: "Edit Protocol") }
        if isAppending, let target = appendTargetProtocol { return String(localized: "Add to \(target.name)") }
        return String(localized: "New Protocol")
    }

    private func appendToExistingStack() {
        guard let target = appendTargetProtocol else { return }
        let peptidesToAdd = orderedSelectedPeptides
            .filter { peptide in !target.peptides.contains { $0.id == peptide.id } }
        guard !peptidesToAdd.isEmpty else { dismiss(); return }
        for peptide in peptidesToAdd {
            dataStore.addPeptide(peptide, toProtocolId: target.id)
        }
        Haptics.success()
        dismiss()
    }

    private var canProceed: Bool {
        guard !selectedPeptides.isEmpty else { return false }
        if isAppending { return true }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canCreate: Bool {
        if isAppending {
            return !selectedPeptides.isEmpty
        }
        if cadenceMode == .interval {
            return canProceed && intervalDays >= 1
        }
        return canProceed && !selectedDays.isEmpty
    }

    private var orderedSelectedPeptides: [Peptide] {
        selectablePeptides.filter { selectedPeptides.contains($0.id) }
    }

    private var selectablePeptides: [Peptide] {
        Self.selectablePeptides(
            catalogue: dataStore.peptideDatabase,
            protocolPeptides: editingProtocol?.peptides ?? []
        )
    }

    /// The catalogue plus the edited protocol's own peptides. Custom
    /// peptides don't sync, so a protocol from another device can hold
    /// one this catalogue lacks — saving must not silently drop it.
    static func selectablePeptides(catalogue: [Peptide], protocolPeptides: [Peptide]) -> [Peptide] {
        let known = Set(catalogue.map(\.id))
        return catalogue + protocolPeptides.filter { !known.contains($0.id) }
    }

    private var defaultSchedule: ProtocolSchedule {
        ProtocolSchedule(
            daysOfWeek: cadenceMode == .weekly ? selectedDays.sorted() : [1, 2, 3, 4, 5, 6, 7],
            timesPerDay: resolvedTimes.count,
            preferredTimes: resolvedTimes,
            intervalDays: cadenceMode == .interval ? intervalDays : nil,
            intervalAnchor: cadenceMode == .interval ? intervalAnchor : nil
        )
    }

    /// `timesPerDay` slots — padded from the default presets — with
    /// duplicates dropped and sorted through the day.
    private var resolvedTimes: [String] {
        var times = preferredTimes
        while times.count < timesPerDay {
            times.append(ScheduleEditor.defaultTimeString(for: times.count))
        }
        return ProtocolSchedule.normalizedTimes(Array(times.prefix(timesPerDay)))
    }

    /// Non-persisted protocol used to drive the live preview share-card render.
    /// Uses `previewID` so the proto's identity is stable across body
    /// invocations — without it, every keystroke would mint a fresh UUID.
    private var previewProtocol: PeptideProtocol {
        PeptideProtocol(
            id: editingProtocol?.id ?? previewID,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "New Protocol") : name,
            peptides: orderedSelectedPeptides,
            schedule: defaultSchedule,
            peptideSchedules: peptideOverrides,
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            startDate: editingProtocol?.startDate ?? previewDate,
            status: .active,
            notes: notes,
            authorName: editingProtocol?.authorName ?? attributionName,
            authorHandle: editingProtocol?.authorHandle,
            forkedFromStackId: editingProtocol?.forkedFromStackId,
            createdAt: editingProtocol?.createdAt ?? previewDate
        )
    }

    /// What the share card actually draws. `PeptideProtocol`'s equality is
    /// id-only, so it can't key the preview task by itself.
    private struct PreviewKey: Hashable {
        let name: String
        let peptideIDs: [UUID]
        let cycleLengthWeeks: Int
    }

    private var previewKey: PreviewKey {
        PreviewKey(
            name: name,
            peptideIDs: orderedSelectedPeptides.map(\.id),
            cycleLengthWeeks: cycleLengthWeeks
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

    private func refreshInlineWarnings() {
        inlineWarnings = StackRecommendationEngine.warnings(
            for: orderedSelectedPeptides,
            activeProtocols: dataStore.activeProtocols
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                        } else {
                            scheduleStep
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                ))
                        }
                    }
                }
            }
            .navigationTitle(builderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: StackLibraryRoute.self) { _ in
                StackLibraryView()
            }
            .navigationDestination(for: CommunityStack.self) { stack in
                CommunityStackDetailView(stack: stack, onUseTemplate: applyTemplate)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep == 0 {
                        Button("Cancel") {
                            if hasUnsavedChanges {
                                isConfirmingDiscard = true
                            } else {
                                dismiss()
                            }
                        }
                        .foregroundStyle(AppColor.textSecondary)
                    } else {
                        Button {
                            Haptics.impact(.light)
                            AppAnimation.with(AppAnimation.step) {
                                currentStep = 0
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                    .font(AppFont.subheadline.weight(.semibold))
                                    .accessibilityHidden(true)
                                Text("Back")
                            }
                            .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == 0 {
                        if isAppending {
                            Button("Add") { appendToExistingStack() }
                                .fontWeight(.semibold)
                                .foregroundStyle(canCreate ? AppColor.accentPrimary : AppColor.textTertiary)
                                .disabled(!canCreate)
                        } else {
                            Button("Next") {
                                Haptics.impact(.light)
                                AppAnimation.with(AppAnimation.step) {
                                    currentStep = 1
                                }
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(canProceed ? AppColor.accentPrimary : AppColor.textTertiary)
                            .disabled(!canProceed)
                        }
                    }
                }
            }
            .onAppear {
                guard !didHydrate else { return }
                didHydrate = true
                if let peptide = preselectedPeptide {
                    selectedPeptides.insert(peptide.id)
                }
                if let proto = editingProtocol {
                    hydrate(from: proto)
                }
                initialForm = currentForm
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("What you've entered for this protocol will be lost.")
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
                .liquidGlassPresentation()
            }
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if !isEditing {
                    startFromCard
                        .sectionAppear(index: 0)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label(isAppending ? "New Peptides" : "Protocol Name", systemImage: isAppending ? "flask.fill" : "pencil")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        if !isAppending {
                            GlassTextField(placeholder: "e.g., Recovery Protocol", text: $name, icon: nil)
                        } else if let target = appendTargetProtocol {
                            Text("Adding to \"\(target.name)\". The peptides you pick below will inherit \(target.schedule.summary).")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
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
                            allPeptides: selectablePeptides,
                            onAddCustomPeptide: { dataStore.addCustomPeptide($0) }
                        )
                    }
                }
                .sectionAppear(index: 2)

                if !inlineWarnings.isEmpty {
                    warningsCard(inlineWarnings)
                        .sectionAppear(index: 3)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .task(id: selectedPeptides) { refreshInlineWarnings() }
    }

    private func hydrate(from proto: PeptideProtocol) {
        name = proto.name
        selectedPeptides = Set(proto.peptides.map(\.id))
        cycleLengthWeeks = proto.cycleLengthWeeks
        washoutWeeks = proto.washoutWeeks
        timesPerDay = proto.schedule.timesPerDay
        notes = proto.notes
        selectedDays = Set(proto.schedule.daysOfWeek)
        peptideOverrides = proto.peptideSchedules
        preferredTimes = proto.schedule.preferredTimes
        if proto.schedule.isInterval, let n = proto.schedule.intervalDays {
            cadenceMode = .interval
            intervalDays = n
            intervalAnchor = proto.schedule.intervalAnchor ?? proto.startDate
        } else {
            cadenceMode = .weekly
        }
    }

    /// "Start from → Template" pre-fills this builder and returns to it,
    /// so the user reviews the template here rather than ending up with
    /// a saved copy behind a builder that can still create a second one.
    private func applyTemplate(_ stack: CommunityStack) {
        hydrate(from: CommunityStackService.shared.forkToProtocol(stack))
        currentStep = 0
        navigationPath = NavigationPath()
    }

    private var isAppending: Bool { appendTargetProtocolId != nil }

    private var appendableProtocols: [PeptideProtocol] {
        dataStore.activeProtocols + dataStore.pausedProtocols
    }

    private var appendTargetProtocol: PeptideProtocol? {
        guard let id = appendTargetProtocolId else { return nil }
        return dataStore.protocols.first { $0.id == id }
    }

    /// One "Start from" row instead of two stacked upsells above the name
    /// field: a library template, or an existing protocol to add to. Once a
    /// target protocol is picked the row turns into its status card.
    private var startFromCard: some View {
        GlassCard(tinted: isAppending) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(isAppending ? "Adding to existing protocol" : "Start from")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(appendCardSubtitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: Spacing.xs)

                if isAppending {
                    startFromButton("Change") {
                        AppAnimation.with(AppAnimation.springSnappy) {
                            appendTargetProtocolId = nil
                        }
                    }
                } else {
                    NavigationLink(value: StackLibraryRoute()) {
                        startFromPill("Template")
                    }
                    .buttonStyle(ScalePressStyle())
                    .minimumHitArea()

                    if !appendableProtocols.isEmpty {
                        startFromButton("Existing") {
                            isShowingAppendPicker = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAppendPicker) {
            AppendStackPickerSheet(
                protocols: appendableProtocols,
                selectedId: appendTargetProtocolId,
                onPick: { id in
                    AppAnimation.with(AppAnimation.springSnappy) {
                        appendTargetProtocolId = id
                    }
                    isShowingAppendPicker = false
                },
                onCancel: { isShowingAppendPicker = false }
            )
            .liquidGlassPresentation(detents: [.medium, .large])
        }
    }

    private func startFromButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            startFromPill(title)
        }
        .buttonStyle(ScalePressStyle())
        .minimumHitArea()
    }

    private func startFromPill(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.chipText)
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + Spacing.xxs)
            .background {
                Capsule().fill(AppColor.accentPrimary.opacity(0.18))
            }
    }

    private var appendCardSubtitle: LocalizedStringKey {
        if let target = appendTargetProtocol {
            return "\(target.name) · ^[\(target.peptides.count) peptide](inflect: true)"
        }
        return "A ready-made template, or a protocol you've already built."
    }

    private func warningsCard(_ warnings: [StackRecommendationEngine.Warning]) -> some View {
        let topWarnings = Array(warnings.prefix(3))
        let hiddenCount = warnings.count - topWarnings.count
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Heads up", systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.warning)

                ForEach(topWarnings) { warning in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: warning.icon)
                            .font(AppFont.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.warning)
                            .frame(width: 18, alignment: .center)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(warning.title)
                                .font(AppFont.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(warning.detail)
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineSpacing(2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
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
                                    .font(AppFont.caption2)
                                    .foregroundStyle(AppColor.accentPrimary)
                            }
                        }

                        Text("Applies to peptides that don't have a custom schedule.")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textTertiary)

                        schedulePresetChips

                        ScheduleEditor(
                            selectedDays: $selectedDays,
                            timesPerDay: $timesPerDay,
                            cycleLengthWeeks: $cycleLengthWeeks,
                            cadenceMode: $cadenceMode,
                            intervalDays: $intervalDays,
                            preferredTimes: $preferredTimes,
                            intervalAnchor: intervalAnchor,
                            dayNames: dayNames
                        )

                        Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)

                        WashoutPicker(washoutWeeks: $washoutWeeks)
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
                                .font(AppFont.caption2)
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
                                        Rectangle().fill(AppColor.glassBorder).frame(height: 0.5)
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

                        GlassTextField(
                            placeholder: "What's this protocol for?",
                            text: $notes,
                            icon: nil,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }
                }
                .sectionAppear(index: 3)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xl)
        }
        // Pinned so the commit action is reachable without scrolling past
        // every schedule control and the notes field.
        .pinnedFooter {
            GlassButton(
                title: isEditing ? "Save Changes" : "Create Protocol",
                icon: isEditing ? "checkmark.circle.fill" : "plus.circle.fill",
                style: .primary,
                isFullWidth: true
            ) {
                isEditing ? saveProtocol() : createProtocol()
            }
            .disabled(!canCreate)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var livePreviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Preview", systemImage: "eye.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if let previewModel {
                    cyclePreview(previewModel)
                } else {
                    SkeletonBlock(
                        width: ShareFormat.story.pixelSize.width * 0.26,
                        height: ShareFormat.story.pixelSize.height * 0.26,
                        cornerRadius: Spacing.controlCornerRadius
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: previewKey) {
            // First render is immediate; later edits settle for a beat so
            // typing a name doesn't redraw the full canvas per keystroke.
            if previewModel != nil {
                try? await Task.sleep(for: AppAnimation.searchDebounceDelay)
                guard !Task.isCancelled else { return }
            }
            previewModel = CycleCardModel.forProtocol(previewProtocol, in: dataStore)
        }
    }

    private func cyclePreview(_ model: CycleCardModel) -> some View {
        CycleCardView(model: model)
            .frame(
                width: ShareFormat.story.pixelSize.width,
                height: ShareFormat.story.pixelSize.height
            )
            .scaleEffect(0.26, anchor: .topLeading)
            .frame(
                width: ShareFormat.story.pixelSize.width * 0.26,
                height: ShareFormat.story.pixelSize.height * 0.26
            )
            .clipShape(RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity)
    }

    private var schedulePresetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            presetChipRow
        }
    }

    private var presetChipRow: some View {
        HStack(spacing: Spacing.sm) {
            GlassChip("Daily", isSelected: isWeeklyPreset([1, 2, 3, 4, 5, 6, 7])) {
                applyWeeklyPreset([1, 2, 3, 4, 5, 6, 7])
            }
            GlassChip("5-on / 2-off", isSelected: isWeeklyPreset([1, 2, 3, 4, 5])) {
                applyWeeklyPreset([1, 2, 3, 4, 5])
            }
            GlassChip("Every other day", isSelected: cadenceMode == .interval && intervalDays == 2) {
                cadenceMode = .interval
                intervalDays = 2
                timesPerDay = 1
            }
        }
    }

    private func isWeeklyPreset(_ days: Set<Int>) -> Bool {
        cadenceMode == .weekly && selectedDays == days && timesPerDay == 1
    }

    private func applyWeeklyPreset(_ days: Set<Int>) {
        cadenceMode = .weekly
        selectedDays = days
        timesPerDay = 1
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
            washoutWeeks: washoutWeeks,
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

        dataStore.updateProtocol(
            id: proto.id,
            name: name.trimmingCharacters(in: .whitespaces),
            peptides: peptides,
            schedule: defaultSchedule,
            peptideSchedules: peptideOverrides,
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Haptics.success()
        dismiss()
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
                    .font(AppFont.scaled(13))
                    .foregroundStyle(peptide.category.color)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                            .fill(peptide.category.color.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(peptide.abbreviation)
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                        if isCustom {
                            Badge("Custom")
                        }
                    }
                    HStack(spacing: 4) {
                        Text(schedule.summary)
                            .font(AppFont.caption2)
                            .foregroundStyle(isCustom ? AppColor.accentLight : AppColor.textTertiary)
                        if let dose = schedule.customDose, !dose.isEmpty {
                            Text("·")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textTertiary)
                            Text(dose)
                                .font(AppFont.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.accentLight)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
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
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }
}

#Preview {
    ProtocolBuilderView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
