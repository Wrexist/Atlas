import SwiftUI

/// "Plan a workout": tap a muscle on the body, keep the companions the
/// engine suggests, and get a hypertrophy session sized to your time.
/// The map shows fatigue until a muscle is picked, then the session's
/// primary and supporting muscles.
struct SessionBuilderSheet: View {
    /// Called with the built routine and whether the session should count
    /// toward it (the user saved it as a routine). The presenter starts the
    /// workout once this sheet is gone: starting it here would present the
    /// workout cover while the sheet is still dismissing, which UIKit drops.
    let onStart: (Routine, _ linksRoutine: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @AppStorage("experienceLevel") private var storedExperience = "beginner"
    @AppStorage("sessionBuilder.minutes") private var minutes = 60
    @State private var library = ExerciseLibrary.shared
    @State private var sessionService = WorkoutSessionService.shared
    @State private var history: [WorkoutSession] = []
    /// Worked out once in `load()`: `DeloadEngine` walks the whole history,
    /// and `preview` reads this on every render.
    @State private var isDeload = false
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
            .navigationTitle(routine == nil ? "Plan a workout" : "Your workout")
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
                Button(isSaved ? LocalizedStringKey("routine.saved") : "Save as routine") { save(routine) }
                    .disabled(isSaved || routine.exercises.isEmpty)
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
                    primaryColor: AppColor.trainingPrimaryMuscleTint,
                    secondaryColor: AppColor.trainingSecondaryMuscleTint,
                    onIdentify: { select(Target($0)) }
                )
                .frame(maxWidth: .infinity)
                .appAnimation(AppAnimation.quick, value: focus)
                // Kept in the layout once a muscle is picked, so the
                // chips below don't jump up when the legend stops applying.
                MuscleHeatLegend(lowLabel: String(localized: "Recovered"),
                                 highLabel: String(localized: "Needs rest"))
                    .opacity(focus == nil ? 1 : 0)
                    .accessibilityHidden(focus != nil)
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

    /// Name and readiness on the left, this week's sets on the right,
    /// and the week's progress as one bar across the card's full width.
    private func statusCard(for target: Target) -> some View {
        let state = states[target]
        let goal = Int(MuscleVolumeTargets.weeklySets(for: profileRequest.experience).lowerBound)
        let done = Int(state?.weeklySets ?? 0)
        let fraction = goal > 0 ? min(1, CGFloat(done) / CGFloat(goal)) : 0
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(target.displayName)
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(statusText(state?.recovery))
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Spacing.sm)
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text("\(done) / \(goal)")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                        Text("sets this week")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Capsule()
                    .fill(AppColor.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(AppColor.trainingPrimaryMuscle)
                            .scaleEffect(x: fraction, anchor: .leading)
                    }
                    .frame(height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(target.displayName))
            .accessibilityValue(Text("\(statusText(state?.recovery)), \(done) of \(goal) sets this week"))
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
            Text(library.displayName(for: slot.exerciseID))
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
                if routine.exercises.isEmpty {
                    Text("No exercises fit your equipment for this. Pick another muscle, or add equipment in Profile.")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    PrimaryCTAButton(title: "Start workout", icon: "play.fill") { start(routine) }
                }
            } else {
                VStack(spacing: Spacing.sm) {
                    if focus == nil {
                        Text("Pick a muscle to start")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    // The same button as "Start workout", which takes this
                    // slot once the workout is built.
                    PrimaryCTAButton(title: "Create workout", icon: "wand.and.stars") { build() }
                        .disabled(focus == nil || !library.isLoaded)
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        // Deeper than the footer's fade, so the fade ends above the
        // button instead of letting the section headers show through it.
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Actions

    private func load() async {
        await library.load()
        await sessionService.refreshReadiness()
        history = dataStore.finishedWorkoutHistory()
        isDeload = DeloadEngine.reason(history: history, now: Date(), calendar: .current) != nil
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
        onStart(routine, isSaved)
        dismiss()
    }
}

#Preview("Plan a workout") {
    SessionBuilderSheet { _, _ in }
        .environment(DataStore(seedSampleData: true))
}
