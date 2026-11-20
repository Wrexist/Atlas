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
    /// The map's two fills, shared with its key so the dots match the
    /// muscles they label in both modes.
    private static let focusColor = AppColor.trainingPrimaryMuscleTint
    private static let companionColor = AppColor.trainingSecondaryMuscleTint
    /// The same orange and blue at ink weight, for the selected muscle
    /// chips: the multiply tints are too pale to fill under
    /// `AppColor.background` ink in light mode.
    private static let focusChipColor = AppColor.trainingPrimaryMuscle
    private static let companionChipColor = AppColor.trainingSecondaryMuscle

    private var profileRequest: ProgramRequest {
        ProgramRequest(profile: dataStore.profile, experienceRaw: storedExperience)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Overlapping, not stacked, while one page hands over to
                // the other: the built workout slides in from the trailing
                // edge and Back brings the picker in from the leading one.
                ZStack(alignment: .top) {
                    if let routine {
                        preview(routine)
                            .transition(.sectionSwap(forward: true))
                    } else {
                        picker
                            .transition(.sectionSwap(forward: false))
                    }
                }
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(routine == nil ? "Plan a workout" : "Your workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // The fade is drawn above the footer instead (see `footer`).
            .pinnedFooter(fadeHeight: 0) { footer }
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
                // Dice, not the wand: the wand is Create workout's, below.
                Button("Pick for me", systemImage: "dice") { pickForMe() }
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
                    primaryColor: Self.focusColor,
                    secondaryColor: Self.companionColor,
                    onIdentify: { select(Target($0)) }
                )
                .frame(maxWidth: .infinity)
                .appAnimation(AppAnimation.quick, value: focus)
                // Recovery heat before a pick, the focus and companion
                // colours after. A key only takes room when it has
                // something to explain, so an untinted map sits right on
                // the chips instead of over a blank slot.
                if focus != nil {
                    roleKey
                        .transition(.opacity)
                } else if showsHeatKey {
                    MuscleHeatLegend(lowLabel: String(localized: "Recovered"),
                                     highLabel: String(localized: "Needs rest"))
                        .transition(.opacity)
                }
            }

            section("MUSCLE") {
                chips(Target.allCases, tint: Self.focusChipColor,
                      isSelected: { $0 == focus }, action: select)
            }

            if let focus {
                statusCard(for: focus)
                section("TRAIN WITH IT") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        chips(focus.companions.filter { !resting.contains($0) },
                              tint: Self.companionChipColor,
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
        .padding(.top, Spacing.lg)
        .padding(.bottom, Self.footerFadeHeight)
    }

    private var showsHeatKey: Bool { !mapHighlights.isEmpty }

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
                            .fill(AppColor.accentPrimary)
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
            // "0 exercises · 0 sets · ~0 min" over the empty state said
            // nothing the empty state doesn't.
            if !routine.exercises.isEmpty {
                Text("\(routine.exercises.count) exercises · \(RoutineSeedEngine.totalSets(in: routine)) sets · ~\(RoutineSeedEngine.estimatedMinutes(for: routine)) min")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            if isDeload {
                Text("Deload week: lighter on purpose so you come back stronger.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            if routine.exercises.isEmpty {
                // In the card the list would fill, so the page keeps its shape.
                GlassCard {
                    EmptyStateView(
                        icon: "dumbbell",
                        title: "No exercises with this equipment",
                        message: "Pick another muscle, or add equipment in Profile.",
                        style: .compact
                    )
                }
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(routine.exercises) { slot in
                            slotRow(slot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Self.footerFadeHeight)
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

    /// What the map's two colours mean once a muscle is picked. The
    /// selected chips below fill in the same orange and blue, so chip,
    /// figure and key all say which muscle plays which role.
    private var roleKey: some View {
        HStack(spacing: Spacing.lg) {
            roleKeyItem("Focus", color: Self.focusColor)
            roleKeyItem("Train with it", color: Self.companionColor)
        }
        .font(AppFont.caption2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func roleKeyItem(_ title: LocalizedStringKey, color: Color) -> some View {
        Label {
            Text(title).foregroundStyle(AppColor.textSecondary)
        } icon: {
            Image(systemName: "circle.fill").foregroundStyle(color)
        }
    }

    private func chips(
        _ targets: [Target],
        tint: Color,
        isSelected: @escaping (Target) -> Bool,
        action: @escaping (Target) -> Void
    ) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(targets, id: \.self) { target in
                GlassChip(LocalizedStringKey(target.displayName), tint: tint, style: .prominent,
                          isSelected: isSelected(target)) {
                    action(target)
                }
            }
        }
    }

    private var footer: some View {
        Group {
            if let routine {
                // Disabled rather than swapped for a caption, so the footer
                // keeps its height and the empty state above says why.
                PrimaryCTAButton(title: "Start workout", icon: "play.fill") { start(routine) }
                    .disabled(routine.exercises.isEmpty)
            } else {
                // The same button as "Start workout", which takes this slot
                // once the workout is built. Until a muscle is picked it
                // names what it's waiting for, so no hint line repeats it.
                if focus == nil {
                    PrimaryCTAButton(title: "Pick a muscle to start") {}
                        .disabled(true)
                } else {
                    PrimaryCTAButton(title: "Create workout", icon: "wand.and.stars") { build() }
                        .disabled(!library.isLoaded)
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .background(alignment: .top) { footerFade }
    }

    /// The soft edge sits above the footer's solid band, not inside it:
    /// a row passing the fold fades out, and nothing is sliced to a
    /// sliver of letter tops at the band's edge. Each page's bottom
    /// padding matches its depth, so at the end of a scroll the fade only
    /// covers padding.
    private var footerFade: some View {
        LinearGradient(colors: [AppColor.background.opacity(0), AppColor.background],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: Self.footerFadeHeight)
            .offset(y: -Self.footerFadeHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let footerFadeHeight = Spacing.xxl

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
