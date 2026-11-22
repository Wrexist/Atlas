import SwiftUI
import UIKit

/// "Plan a workout": say where you train, tap a muscle on the body, keep
/// the companions the engine suggests, and get a hypertrophy session sized
/// to your time and built only from the kit you have. The built workout
/// shows how each exercise is done before you start.
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
    @State private var equipmentStore = EquipmentProfileStore.shared
    @State private var history: [WorkoutSession] = []
    /// Worked out once in `load()`: `DeloadEngine` walks the whole history,
    /// and `preview` reads this on every render.
    @State private var isDeload = false
    @State private var recovery: [AnatomicalMuscle: MuscleRecoveryEngine.Recovery] = [:]
    @State private var states: [Target: SessionBuilderEngine.State] = [:]
    @State private var focus: Target?
    @State private var companions: [Target] = []
    @State private var resting: [Target] = []
    @State private var built: Built?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var isSaved = false
    @State private var showsEquipment = false
    @State private var detailExercise: Exercise?
    /// Bumped by each pick from the muscle list, to scroll its next step in.
    @State private var listPicks = 0

    private typealias Target = SessionBuilderEngine.Target
    private static let minuteOptions = [30, 45, 60, 75]
    private static let focusAnchor = "focus"
    /// The map's two fills, shared with its key so the dots match the
    /// muscles they label in both modes.
    private static let focusColor = AppColor.trainingPrimaryMuscleTint
    private static let companionColor = AppColor.trainingSecondaryMuscleTint
    /// The same orange and blue at ink weight, for the selected muscle
    /// chips: the multiply tints are too pale to fill under
    /// `AppColor.background` ink in light mode.
    private static let focusChipColor = AppColor.trainingPrimaryMuscle
    private static let companionChipColor = AppColor.trainingSecondaryMuscle
    private static let pictureHeight: CGFloat = 132
    /// The exercise number's circle grows with the number's text size.
    @ScaledMetric(relativeTo: .footnote) private var badgeSize: CGFloat = 30

    /// The built session with what its page draws, worked out once when it
    /// is built rather than on every render: step pictures are a bundle
    /// lookup per exercise, the session map a pass over every lift.
    private struct Built {
        var plan: SessionBuilderEngine.Plan
        var exercises: [String: Exercise]
        var steps: [String: [String]]
        var highlights: [AnatomicalMuscle: MuscleHighlight]
        var routine: Routine { plan.routine }
    }

    private var profileRequest: ProgramRequest {
        ProgramRequest(profile: dataStore.profile, experienceRaw: storedExperience)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                    // Overlapping, not stacked, while one page hands over to
                    // the other: the built workout slides in from the trailing
                    // edge and Back brings the picker in from the leading one.
                    ZStack(alignment: .top) {
                        if let built {
                            preview(built)
                                .transition(.sectionSwap(forward: true))
                        } else {
                            picker
                                .transition(.sectionSwap(forward: false))
                        }
                    }
                    .readableContentWidth()
                    // A muscle picked by name, low on the page, brings its
                    // next step into view; one tapped on the body already
                    // sits right above it.
                    .onChange(of: listPicks) {
                        AppAnimation.with(AppAnimation.springSnappy) {
                            proxy.scrollTo(Self.focusAnchor, anchor: .top)
                        }
                    }
                }
            }
            // Each page opens at its top, not where the other was left.
            .scrollPosition($scroll)
            .modifier(SolidTopEdge())
            .onChange(of: built == nil) { scroll.scrollTo(edge: .top) }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(built == nil ? "Plan a workout" : "Your workout")
            .navigationBarTitleDisplayMode(.inline)
            // A solid bar, so chips and pictures scrolling up never run
            // under the title and its buttons.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { toolbar }
            // The fade is drawn above the footer instead (see `footer`).
            .pinnedFooter(fadeHeight: 0) { footer }
            .task { await load() }
            // A muscle tapped before recovery loaded gets its companions
            // again once it has, so resting ones drop out.
            .onChange(of: states) { if let focus { suggestCompanions(for: focus) } }
            .sheet(isPresented: $showsEquipment) {
                EquipmentProfileSheet(location: equipmentStore.location)
            }
            .sheet(item: $detailExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(exerciseID: exercise.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { detailExercise = nil }
                            }
                        }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if built == nil {
                Button("Cancel") { dismiss() }
            } else {
                Button("Back") { AppAnimation.with(AppAnimation.springSnappy) { built = nil } }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let built {
                Button(isSaved ? LocalizedStringKey("routine.saved") : "Save") { save(built.routine) }
                    .accessibilityLabel(isSaved ? Text("routine.saved") : Text("Save as routine"))
                    .disabled(isSaved || built.routine.exercises.isEmpty)
            } else {
                // Dice, not the wand: the wand is Create workout's, below.
                Button("Pick for me", systemImage: "dice") { pickForMe() }
                    .disabled(states.isEmpty)
            }
        }
    }

    // MARK: - Picking

    private var picker: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            placeCard
            bodyPicker(mapHighlights)

            // What a pick decides sits right under the body, so tapping a
            // muscle shows its next step without a scroll; the full list of
            // muscles follows for picking by name.
            if let focus {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(Self.focusAnchor)
            }

            section("MINUTES") {
                GlassSegmentedControl(options: Self.minuteOptions, selected: $minutes,
                                      label: { LocalizedStringKey("\($0)") })
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Target.Category.allCases, id: \.self) { category in
                    categoryGroup(category)
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Self.footerFadeHeight)
    }

    /// Where you train, and the kit that place has. The place decides
    /// which exercises the session may use.
    private var placeCard: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                GlassSegmentedControl(
                    options: TrainingLocation.allCases,
                    selected: Binding(get: { equipmentStore.location },
                                      set: { place in
                                          Haptics.selection()
                                          equipmentStore.select(place)
                                      }),
                    label: { LocalizedStringKey($0.displayName) },
                    icon: { $0.symbol }
                )
                Button { showsEquipment = true } label: {
                    HStack(spacing: Spacing.md) {
                        GlyphImage(glyph: EquipmentKind.dumbbell.glyph, size: 15)
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 28, height: 28)
                        Text("Equipment")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer(minLength: Spacing.sm)
                        Text("\(equipmentStore.current.itemCount) selected")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .frame(minHeight: Spacing.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cardPress)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Choose the equipment you have"))
            }
        }
        .appAnimation(AppAnimation.quick, value: equipmentStore.location)
    }

    /// The body is the picker: a tapped muscle becomes the focus and the
    /// figure lights it orange, its companions blue.
    private func bodyPicker(_ highlights: [AnatomicalMuscle: MuscleHighlight]) -> some View {
        VStack(spacing: Spacing.md) {
            MuscleMapView(
                highlights: highlights,
                primaryColor: Self.focusColor,
                secondaryColor: Self.companionColor,
                onIdentify: { select(Target($0)) }
            )
            .frame(maxWidth: .infinity)
            .appAnimation(AppAnimation.settle, value: highlights)
            // One line under the figure that always says something: how to
            // pick before a pick, then what the two colours mean.
            Group {
                if focus != nil {
                    roleKey
                } else if !highlights.isEmpty {
                    MuscleHeatLegend(lowLabel: String(localized: "Recovered"),
                                     highLabel: String(localized: "Needs rest"))
                } else {
                    Text("Tap a muscle on the body")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .transition(.opacity)
        }
        .appAnimation(AppAnimation.quick, value: focus)
    }

    /// Fatigue heat before a pick; the session's muscles after.
    private var mapHighlights: [AnatomicalMuscle: MuscleHighlight] {
        guard let focus else {
            return recovery.compactMapValues { $0.fraction < 1 ? .intensity(1 - $0.fraction) : nil }
        }
        return Self.roleHighlights(focus: focus, others: companions)
    }

    /// Orange for the focus, blue for every other muscle in the session:
    /// the same meaning on the picker and on the built workout.
    private static func roleHighlights(focus: Target, others: [Target]) -> [AnatomicalMuscle: MuscleHighlight] {
        var map: [AnatomicalMuscle: MuscleHighlight] = [:]
        for other in others {
            for head in other.heads { map[head] = .secondary }
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
                            .contentTransition(.opacity)
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
                            .contentTransition(.numericText())
                        Text("sets this week")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                // An empty bar says nothing the "0 / 10" doesn't.
                if done > 0 {
                    Capsule()
                        .fill(AppColor.track)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.accentPrimary)
                                .scaleEffect(x: fraction, anchor: .leading)
                        }
                        .frame(height: 6)
                        .appAnimation(AppAnimation.settle, value: fraction)
                }
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

    // MARK: - The built workout

    private func preview(_ built: Built) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if built.routine.exercises.isEmpty {
                // In the card the list would fill, so the page keeps its shape.
                GlassCard {
                    EmptyStateView(
                        icon: "dumbbell",
                        title: "No exercises with this equipment",
                        message: "Pick another muscle, or tick more equipment.",
                        action: .init(title: "Equipment") { showsEquipment = true },
                        style: .compact
                    )
                }
            } else {
                summaryCard(built)
                notes(built)
                ForEach(Array(built.routine.exercises.enumerated()), id: \.element.id) { index, slot in
                    exerciseCard(slot, number: index + 1, in: built)
                        .scrollReveal()
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Self.footerFadeHeight)
    }

    /// The session at a glance: its name, the whole body with every muscle
    /// it trains, and three equal columns for exercises, sets and minutes.
    private func summaryCard(_ built: Built) -> some View {
        let routine = built.routine
        return GlassCard {
            VStack(spacing: Spacing.lg) {
                VStack(spacing: Spacing.xxs) {
                    Text(routine.name)
                        .font(AppFont.scaled(24, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                    if let subtitle = routine.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppFont.scaled(13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                MuscleMapView(
                    highlights: built.highlights,
                    primaryColor: Self.focusColor,
                    secondaryColor: Self.companionColor,
                    identifiesOnTap: false
                )
                .frame(height: 190)
                .frame(maxWidth: .infinity)

                HStack(spacing: 0) {
                    stat(routine.exercises.count, label: "Exercises")
                    statDivider
                    stat(RoutineSeedEngine.totalSets(in: routine), label: "Sets")
                    statDivider
                    stat(Int((Double(ProgramGeneratorEngine.plannedSeconds(for: routine)) / 60).rounded()), label: "Minutes")
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stat(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text("\(value)")
                .font(AppFont.scaled(20, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(AppColor.glassBorder)
            .frame(width: 1, height: 32)
            .accessibilityHidden(true)
    }

    /// Why the session holds more than was picked, and the deload note.
    @ViewBuilder
    private func notes(_ built: Built) -> some View {
        let added = built.plan.added.map(\.displayName).formatted(.list(type: .and))
        if !built.plan.added.isEmpty || isDeload {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !built.plan.added.isEmpty {
                    note("plus.circle", Text("Added \(added) to fill your \(minutes) minutes."))
                }
                if isDeload {
                    note("leaf", Text("Deload week: lighter on purpose so you come back stronger."))
                }
            }
        }
    }

    private func note(_ icon: String, _ text: Text) -> some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(AppColor.accentPrimary)
        }
        .font(AppFont.scaled(13))
        .foregroundStyle(AppColor.textSecondary)
    }

    /// One exercise: how it's done on top (step pictures, or the muscle
    /// map where there are none yet), then its number, name and targets.
    /// Tapping opens the full exercise page.
    private func exerciseCard(_ slot: RoutineExercise, number: Int, in built: Built) -> some View {
        let exercise = built.exercises[slot.exerciseID]
        let steps = built.steps[slot.exerciseID] ?? []
        return Button { detailExercise = exercise } label: {
            GlassCard {
                VStack(spacing: Spacing.lg) {
                    Group {
                        if steps.isEmpty {
                            ExerciseHeroView(exercise: exercise, interactive: false)
                        } else {
                            ExerciseStepStrip(assetNames: steps, height: Self.pictureHeight)
                        }
                    }
                    .frame(height: Self.pictureHeight)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)

                    HStack(spacing: Spacing.md) {
                        Text("\(number)")
                            .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.accentPrimary)
                            .monospacedDigit()
                            .frame(width: badgeSize, height: badgeSize)
                            .background(Circle().fill(AppColor.accentPrimary.opacity(0.15)))
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(library.displayName(for: slot.exerciseID))
                                .font(AppFont.scaled(16, weight: .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(detail(for: slot))
                                .font(AppFont.scaled(13))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.cardPress)
        .disabled(exercise == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(for: slot, number: number))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows how to do it"))
    }

    /// The row as a sentence: "×" and a clock-style rest read badly aloud.
    private func spokenLabel(for slot: RoutineExercise, number: Int) -> Text {
        let rest = Duration.seconds(slot.restSeconds ?? 0).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        let effort = (slot.targetRPE ?? 0).formatted()
        let name = library.displayName(for: slot.exerciseID)
        return Text("Exercise \(number), \(name), \(slot.targetSets) sets of \(slot.targetReps) reps, RPE \(effort), \(rest) rest")
    }

    private func detail(for slot: RoutineExercise) -> LocalizedStringKey {
        let rest = Duration.seconds(slot.restSeconds ?? 0).formatted(.time(pattern: .minuteSecond))
        let effort = (slot.targetRPE ?? 0).formatted()
        return slot.supersetGroup == nil
            ? "\(slot.targetSets) × \(slot.targetReps) · RPE \(effort) · \(rest) rest"
            : "\(slot.targetSets) × \(slot.targetReps) · RPE \(effort) · \(rest) rest · Superset"
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

    /// One body region: its name, then its muscles as chips.
    private func categoryGroup(_ category: Target.Category) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(category.displayName)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            chips(category.targets, tint: Self.focusChipColor,
                  isSelected: { $0 == focus }) { target in
                select(target)
                listPicks += 1
            }
        }
    }

    private func chips(
        _ targets: [Target],
        tint: Color,
        isSelected: @escaping (Target) -> Bool,
        action: @escaping (Target) -> Void
    ) -> some View {
        FlowLayout(spacing: Spacing.chipSpacing) {
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
            if let built {
                // Disabled rather than swapped for a caption, so the footer
                // keeps its height and the empty state above says why.
                PrimaryCTAButton(title: "Start workout", icon: "play.fill") { start(built.routine) }
                    .disabled(built.routine.exercises.isEmpty)
            } else if focus == nil {
                // The same button as "Start workout", which takes this slot
                // once the workout is built. Until a muscle is picked it
                // names what it's waiting for, so no hint line repeats it.
                PrimaryCTAButton(title: "Pick a muscle to start") {}
                    .disabled(true)
            } else {
                // Waits for recovery too: built before it, the session
                // would ignore which muscles should rest.
                PrimaryCTAButton(title: "Create workout", icon: "wand.and.stars") { build() }
                    .disabled(!library.isLoaded || states.isEmpty)
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

    /// Deep enough that a chip row passing under it fades out whole.
    private static let footerFadeHeight = Spacing.xxxl

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
        suggestCompanions(for: target)
    }

    private func suggestCompanions(for target: Target) {
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
            equipment: equipmentStore.current,
            states: states,
            familiarExerciseIDs: Set(history.flatMap { $0.exercises.map(\.exerciseID) }),
            isDeload: isDeload
        )
        let plan = SessionBuilderEngine.build(request, catalog: library.bundled)
        let ids = plan.routine.exercises.map(\.exerciseID)
        let exercises = Dictionary(ids.compactMap { id in library.lookup(id: id).map { (id, $0) } },
                                   uniquingKeysWith: { first, _ in first })
        let result = Built(
            plan: plan,
            exercises: exercises,
            steps: Dictionary(ids.map { ($0, ExerciseStepArt.assetNames(for: $0)) }, uniquingKeysWith: { first, _ in first }),
            highlights: Self.roleHighlights(focus: focus, others: plan.others)
        )
        Haptics.impact(.light)
        isSaved = false
        AppAnimation.with(AppAnimation.springSnappy) { built = result }
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

/// iOS 26 lets content slide under the glass toolbar with only a soft
/// fade, so chips and pictures read through the title and its buttons.
/// The hard edge gives the bar a defined backdrop; earlier systems get
/// the solid bar from `toolbarBackground`.
private struct SolidTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

#Preview("Plan a workout") {
    SessionBuilderSheet { _, _ in }
        .environment(DataStore(seedSampleData: true))
}
