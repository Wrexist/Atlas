import SwiftUI

/// "Build my program": five answers in, a week of routines out. The form
/// opens prefilled from onboarding, `ProgramGeneratorEngine` does the
/// building, and the preview lets the user swap any exercise for another
/// that does the same job before `onSave` hands the days to the library.
struct ProgramBuilderSheet: View {
    let onSave: ([Routine]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @AppStorage("experienceLevel") private var storedExperience: String = "beginner"
    @State private var library = ExerciseLibrary.shared
    @State private var request = ProgramRequest()
    @State private var program: GeneratedProgram?
    /// Swap options per slot, resolved when the program changes rather
    /// than on every render of the preview.
    @State private var alternatives: [UUID: [String]] = [:]
    @State private var didPrefill = false

    /// The rest the timer runs for a slot and routine that set none.
    private var defaultRestSeconds: Int {
        dataStore.profile.trainingPreferences?.restTimerDefault ?? RoutineSeedEngine.fallbackRestSeconds
    }

    /// Onboarding's equipment vocabulary, so a prefilled answer can be
    /// toggled off here. Bodyweight is always in, and a foam roller has
    /// no lift in the shortlist to unlock.
    private static let equipmentChoices = EquipmentKind.accessChoices.filter {
        $0 != .bodyweight && $0 != .foamRoller
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let program {
                    preview(program)
                } else {
                    form
                }
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(program == nil ? "Build my program" : "Your program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if program == nil {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back") {
                            AppAnimation.with(AppAnimation.springSnappy) { program = nil }
                        }
                    }
                }
            }
            .pinnedFooter { footer }
            .task {
                await library.load()
                prefill()
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            section("GOAL") {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(TrainingGoal.allCases) { goal in
                        GlassChip(LocalizedStringKey(goal.displayName), isSelected: request.goal == goal) {
                            request.goal = goal
                        }
                    }
                }
            }

            section("EXPERIENCE") {
                GlassSegmentedControl(
                    options: [Exercise.Level.beginner, .intermediate, .expert],
                    selected: $request.experience,
                    label: { LocalizedStringKey($0.displayName) }
                )
            }

            section("DAYS PER WEEK") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    GlassSegmentedControl(
                        options: Array(ProgramRequest.dayRange),
                        selected: $request.daysPerWeek,
                        label: { LocalizedStringKey("\($0)") }
                    )
                    Text(plannedSplit.displayName)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            section("MINUTES PER SESSION") {
                GlassSegmentedControl(
                    options: ProgramRequest.sessionOptions,
                    selected: $request.sessionMinutes,
                    label: { LocalizedStringKey("\($0)") }
                )
            }

            section("EQUIPMENT") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(Self.equipmentChoices) { kind in
                            GlassChip(
                                LocalizedStringKey(kind.displayName),
                                glyph: kind.glyph,
                                isSelected: request.equipment.contains(kind)
                            ) {
                                toggle(kind)
                            }
                        }
                    }
                    Text("Bodyweight moves are always included.")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.lg)
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// The split the generator will build for these answers, so the hint
    /// matches the preview. Falls back to the day-count split until the
    /// library has loaded — an empty catalog can fill no day.
    private var plannedSplit: TrainingSplit {
        guard library.isLoaded else { return TrainingSplit.forDays(request.daysPerWeek) }
        return ProgramGeneratorEngine.split(for: request, catalog: library.bundled)
    }

    // MARK: - Preview

    private func preview(_ program: GeneratedProgram) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("\(program.split.displayName) · \(program.days.count) days a week · up to \(program.request.sessionMinutes) min")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)

            ForEach(program.days) { day in
                dayCard(day, in: program)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.lg)
    }

    private func dayCard(_ day: GeneratedDay, in program: GeneratedProgram) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(day.routine.name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(day.routine.exercises.count) exercises · \(RoutineSeedEngine.totalSets(in: day.routine)) sets · ~\(RoutineSeedEngine.estimatedMinutes(for: day.routine, defaultRestSeconds: defaultRestSeconds)) min")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                ForEach(day.routine.exercises.sorted { $0.index < $1.index }) { slot in
                    slotRow(slot, in: day)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func slotRow(_ slot: RoutineExercise, in day: GeneratedDay) -> some View {
        let name = library.lookup(id: slot.exerciseID)?.name ?? slot.exerciseID
        let pattern = day.patterns[slot.id]?.displayName ?? ""
        let detail = slot.supersetGroup == nil
            ? "\(slot.targetSets) × \(slot.targetReps) · \(pattern)"
            : "\(slot.targetSets) × \(slot.targetReps) · \(pattern) · Superset"
        let options = alternatives[slot.id] ?? []
        return HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text(detail)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { exerciseID in
                        Button(library.lookup(id: exerciseID)?.name ?? exerciseID) {
                            swap(slot.id, to: exerciseID)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                }
                .accessibilityLabel("Swap \(name)")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if program == nil {
                GlassButton(title: "Build my program", icon: "wand.and.stars", isFullWidth: true) {
                    build()
                }
                .disabled(!library.isLoaded)
            } else {
                GlassButton(title: "Save program", icon: "checkmark", isFullWidth: true) {
                    save()
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Actions

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        request = ProgramRequest(profile: dataStore.profile, experienceRaw: storedExperience)
    }

    private func toggle(_ kind: EquipmentKind) {
        if request.equipment.contains(kind) {
            request.equipment.remove(kind)
        } else {
            request.equipment.insert(kind)
        }
    }

    private func build() {
        let generated = ProgramGeneratorEngine.generate(request, catalog: library.bundled)
        refreshAlternatives(for: generated)
        AppAnimation.with(AppAnimation.springSnappy) { program = generated }
    }

    private func swap(_ slotID: UUID, to exerciseID: String) {
        guard let program else { return }
        Haptics.selection()
        let swapped = ProgramGeneratorEngine.swapping(slotID: slotID, to: exerciseID, in: program)
        refreshAlternatives(for: swapped)
        self.program = swapped
    }

    private func refreshAlternatives(for program: GeneratedProgram) {
        var options: [UUID: [String]] = [:]
        for day in program.days {
            for slot in day.routine.exercises {
                options[slot.id] = ProgramGeneratorEngine.alternatives(
                    forSlot: slot.id, in: day, request: program.request, catalog: library.bundled
                )
            }
        }
        alternatives = options
    }

    private func save() {
        guard let program else { return }
        Haptics.success()
        onSave(program.routines)
        dismiss()
    }
}

#Preview("Build my program") {
    ProgramBuilderSheet { _ in }
        .environment(DataStore(seedSampleData: true))
}
