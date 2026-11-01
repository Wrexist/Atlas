import SwiftUI

/// "Build workout": tap a muscle on the body, keep the companions the
/// engine suggests, and get a hypertrophy session sized to your time.
/// The map shows fatigue until a muscle is picked, then the session's
/// primary and supporting muscles.
struct SessionBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @AppStorage("experienceLevel") private var storedExperience = "beginner"
    @AppStorage("sessionBuilder.minutes") private var minutes = 60
    @State private var library = ExerciseLibrary.shared
    @State private var sessionService = WorkoutSessionService.shared
    @State private var history: [WorkoutSession] = []
    @State private var recovery: [AnatomicalMuscle: MuscleRecoveryEngine.Recovery] = [:]
    @State private var states: [Target: SessionBuilderEngine.State] = [:]
    @State private var focus: Target?
    @State private var companions: [Target] = []
    @State private var resting: [Target] = []
    @State private var routine: Routine?
    @State private var isSaved = false

    private typealias Target = SessionBuilderEngine.Target
    private static let minuteOptions = [30, 45, 60, 75]

    private var profileRequest: ProgramRequest {
        ProgramRequest(profile: dataStore.profile, experienceRaw: storedExperience)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let routine {
                    preview(routine)
                } else {
                    picker
                }
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(routine == nil ? "Build workout" : "Your workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .pinnedFooter { footer }
            .task { await load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if routine == nil {
                Button("Cancel") { dismiss() }
            } else {
                Button("Back") { AppAnimation.with(AppAnimation.springSnappy) { routine = nil } }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let routine {
                Button(isSaved ? LocalizedStringKey("Saved") : "Save as routine") { save(routine) }
                    .disabled(isSaved)
            } else {
                Button("Pick for me", systemImage: "wand.and.stars") { pickForMe() }
                    .disabled(states.isEmpty)
            }
        }
    }

    // MARK: - Picking muscles

    private var picker: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                MuscleMapView(
                    highlights: mapHighlights,
                    primaryColor: AppColor.trainingPrimaryMuscle,
                    secondaryColor: AppColor.trainingSecondaryMuscle,
                    onIdentify: { select(Target($0)) }
                )
                .frame(maxWidth: .infinity)
                .appAnimation(AppAnimation.quick, value: focus)
                if focus == nil {
                    MuscleHeatLegend(lowLabel: String(localized: "Recovered"),
                                     highLabel: String(localized: "Needs rest"))
                }
            }

            section("MUSCLE") {
                chips(Target.allCases, isSelected: { $0 == focus }, action: select)
            }

            if let focus {
                statusCard(for: focus)
                section("TRAIN WITH IT") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        chips(focus.companions.filter { !resting.contains($0) },
                              isSelected: { companions.contains($0) },
                              action: toggleCompanion)
                        if !resting.isEmpty {
                            Text("Resting today: \(resting.map(\.displayName).formatted(.list(type: .and)))")
                                .font(AppFont.scaled(13))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
            }

            section("MINUTES") {
                GlassSegmentedControl(options: Self.minuteOptions, selected: $minutes,
                                      label: { LocalizedStringKey("\($0)") })
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.lg)
    }

    /// Fatigue heat before a pick; the session's muscles after.
    private var mapHighlights: [AnatomicalMuscle: MuscleHighlight] {
        guard let focus else {
            return recovery.compactMapValues { $0.fraction < 1 ? .intensity(1 - $0.fraction) : nil }
        }
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        for companion in companions {
            for head in companion.heads { map[head] = .secondary }
        }
        for head in focus.heads { map[head] = .primary }
        return map
    }

    private func statusCard(for target: Target) -> some View {
        let state = states[target]
        let goal = Int(MuscleVolumeTargets.weeklySets(for: profileRequest.experience).lowerBound)
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(target.displayName)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(statusText(state?.recovery))
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
                Text("\(Int(state?.weeklySets ?? 0)) of \(goal) sets this week")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func statusText(_ recovery: MuscleRecoveryEngine.Recovery?) -> String {
        guard let recovery else { return String(localized: "Ready to train") }
        let percent = Int((recovery.fraction * 100).rounded())
        switch recovery.status {
        case .ready: return String(localized: "Ready to train")
        case .recovering: return String(localized: "\(percent)% recovered, a little less volume today")
        case .rest: return String(localized: "\(percent)% recovered, best to rest it today. You can still train it, lighter.")
        }
    }

    // MARK: - Preview

    private func preview(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("\(routine.exercises.count) exercises · \(RoutineSeedEngine.totalSets(in: routine)) sets · ~\(RoutineSeedEngine.estimatedMinutes(for: routine)) min")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
            if isDeload {
                Text("Deload week: lighter on purpose so you come back stronger.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(routine.exercises) { slot in
                        slotRow(slot)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.lg)
    }

    private func slotRow(_ slot: RoutineExercise) -> some View {
        let rest = Duration.seconds(slot.restSeconds ?? 0).formatted(.time(pattern: .minuteSecond))
        let effort = (slot.targetRPE ?? 0).formatted()
        let detail: LocalizedStringKey = slot.supersetGroup == nil
            ? "\(slot.targetSets) × \(slot.targetReps) · RPE \(effort) · \(rest) rest"
            : "\(slot.targetSets) × \(slot.targetReps) · RPE \(effort) · \(rest) rest · Superset"
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(library.lookup(id: slot.exerciseID)?.name ?? slot.exerciseID)
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
            Text(detail)
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

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

    private func chips(
        _ targets: [Target],
        isSelected: @escaping (Target) -> Bool,
        action: @escaping (Target) -> Void
    ) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(targets, id: \.self) { target in
                GlassChip(LocalizedStringKey(target.displayName), isSelected: isSelected(target)) {
                    action(target)
                }
            }
        }
    }

    private var footer: some View {
        Group {
            if let routine {
                PrimaryCTAButton(title: "Start workout", icon: "play.fill") { start(routine) }
            } else {
                GlassButton(title: "Build workout", icon: "wand.and.stars", isFullWidth: true) { build() }
                    .disabled(focus == nil || !library.isLoaded)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Actions

    private var isDeload: Bool {
        DeloadEngine.reason(history: history, now: Date(), calendar: .current) != nil
    }

    private func load() async {
        await library.load()
        await sessionService.refreshReadiness()
        history = TrainOverviewView.finishedHistory(SwiftDataRepository.shared.loadAllWorkoutSessions())
        recovery = MuscleRecoveryEngine.recovery(from: history, library: library,
                                                 readiness: sessionService.readiness.level)
        states = SessionBuilderEngine.states(
            recovery: recovery,
            weekly: WeeklyMuscleHeatmap.frequencies(from: history, library: library)
        )
    }

    private func select(_ target: Target) {
        Haptics.selection()
        let suggestion = SessionBuilderEngine.companions(
            for: target, states: states, experience: profileRequest.experience
        )
        AppAnimation.with(AppAnimation.springSnappy) {
            focus = target
            resting = suggestion.resting
            companions = Array(suggestion.suggested.prefix(2))
        }
    }

    private func toggleCompanion(_ target: Target) {
        Haptics.selection()
        AppAnimation.with(AppAnimation.springSnappy) {
            if let index = companions.firstIndex(of: target) {
                companions.remove(at: index)
            } else {
                companions.append(target)
            }
        }
    }

    private func pickForMe() {
        guard let target = SessionBuilderEngine.smartFocus(states: states, experience: profileRequest.experience)
        else { return }
        select(target)
    }

    private func build() {
        guard let focus else { return }
        let request = SessionBuilderEngine.Request(
            focus: focus,
            companions: companions,
            minutes: minutes,
            experience: profileRequest.experience,
            equipment: profileRequest.equipment,
            states: states,
            familiarExerciseIDs: Set(history.flatMap { $0.exercises.map(\.exerciseID) }),
            isDeload: isDeload
        )
        let built = SessionBuilderEngine.build(request, catalog: library.bundled)
        isSaved = false
        AppAnimation.with(AppAnimation.springSnappy) { routine = built }
    }

    private func save(_ routine: Routine) {
        Haptics.success()
        RoutineStore.shared.add([routine])
        isSaved = true
    }

    private func start(_ routine: Routine) {
        Haptics.impact(.medium)
        sessionService.startWorkout(routine: routine, linksRoutine: false)
        dismiss()
    }
}

#Preview("Build workout") {
    SessionBuilderSheet()
        .environment(DataStore(seedSampleData: true))
}
