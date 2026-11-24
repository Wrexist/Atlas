import SwiftUI

/// Train tab landing surface — "Översikt" in the Lyfta reference.
/// Built around layered cards:
///
///   0. **This week** — the lit hero: a mark per day trained, counted
///      against the training-days goal when the user set one.
///   1. **Weekly muscle map** — anatomical figure that lights up the
///      muscles the user actually trained over the past 7 days. The
///      whole body stays visible at a low baseline so the surface
///      reads even on a fresh install.
///   2. **Latest workout** — the most recent session, with "View all"
///      pushing the full history; before the first session, a few
///      one-tap starters instead.
///   3. **Month calendar** — heat-by-day grid for the current month.
///      Days the user trained pulse with the accent colour; rest days
///      stay calm. Mirrors the shape of the existing peptide
///      compliance calendar so the visual language is consistent
///      across tabs.
struct TrainOverviewView: View {
    @Binding var scrollPosition: ScrollPosition
    @Environment(DataStore.self) private var dataStore
    @State private var library = ExerciseLibrary.shared
    /// Finished sessions, newest first, capped like the History list:
    /// the recent row, calendar, period maps and regularity.
    @State private var sessions: [WorkoutSession] = []
    /// Every finished session. The all-time Total map and the "All
    /// workouts" sheet promise every session, which the cap would break.
    @State private var allSessions: [WorkoutSession] = []
    @State private var sessionService = WorkoutSessionService.shared
    @State private var routineStore = RoutineStore.shared
    /// Memoised result of `WeeklyMuscleHeatmap.frequencies` — the
    /// underlying scan is O(sessions × exercises × muscles) and was
    /// previously recomputed on every body re-evaluation because the
    /// `weekHasTraining` and `weeklyMuscleCard` paths
    /// both touched the computed property. Recomputed only when
    /// `refresh()` runs (i.e. when sessions actually change).
    @State private var frequencies: [AnatomicalMuscle: Double] = [:]
    @State private var weekSummary = TrainWeekSummary.empty
    /// All-time per-muscle volume + 12-week training regularity for the
    /// "Muscle gains" card. Memoised alongside `frequencies` — same
    /// O(sessions × exercises × muscles) scan, same refresh cadence.
    @State private var totalFrequencies: [AnatomicalMuscle: Double] = [:]
    @State private var regularity: [AnatomicalMuscle: Double] = [:]
    /// The muscle the user tapped on the map, presented as a detail sheet
    /// of the exercises they've logged for it.
    @State private var inspectedMuscle: AnatomicalMuscle?
    @SceneStorage("train.overview.period") private var selectedPeriodRaw = 7
    private var selectedPeriod: TrainingMapPeriod { TrainingMapPeriod(rawValue: selectedPeriodRaw) ?? .week }
    @State private var inspectedDays: Int? = 7
    @State private var inspectedPeriodLabel = String(localized: "Last 7 days")
    @SceneStorage("train.overview.details") private var showsTrainingDetails = false
    @State private var showsMapInfo = false
    @State private var bodyFacing: BodyFacing = .both
    @State private var showsSessionBuilder = false
    /// The builder's routine, started once its sheet has finished dismissing.
    @State private var builtWorkout: (routine: Routine, linksRoutine: Bool)?

    private enum TrainingMapPeriod: Int, CaseIterable {
        case today = 1, week = 7, month = 30
        var title: String {
            switch self {
            case .today: String(localized: "Today")
            case .week: String(localized: "7 days")
            case .month: String(localized: "30 days")
            }
        }
        var detail: String { self == .today ? String(localized: "Today") : String(localized: "Last \(rawValue) days") }
    }
    /// Personalization brief Phase 9/10: a one-line read on how this
    /// week's session count compares to this user's own recent training
    /// history — never a population norm, and `nil` (not a guess) below
    /// `TrainingPatternEngine.emergingAtWeeks` of history. Memoised
    /// alongside `frequencies` since both are derived from `sessions`.
    @State private var trainingContextCaption: String?

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    private var weekHasTraining: Bool {
        !frequencies.isEmpty
    }

    /// Training inside the widest period, so the map has something to
    /// light up and switching periods can change it.
    private var hasTrainingToFilter: Bool {
        let calendar = Calendar.current
        let widest = TrainingMapPeriod.allCases.map(\.rawValue).max() ?? 1
        guard let cutoff = calendar.date(byAdding: .day, value: -(widest - 1), to: calendar.startOfDay(for: Date()))
        else { return true }
        return sessions.contains { $0.startedAt >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                weekHero
                    .sectionAppear(index: 0)
                startWorkoutButton
                    .sectionAppear(index: 1)
                recentWorkoutsCard
                    .sectionAppear(index: 2)
                // An unlit body map is a full screen of nothing; it shows
                // once there is training for its periods to light up.
                if hasTrainingToFilter {
                    weeklyMuscleCard
                        .sectionAppear(index: 3)
                }
                trainingDetails
                    .scrollReveal()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .scrollPosition($scrollPosition)
        // Re-reads the store: the bump drops the cached history and
        // re-runs the `.task(id:)` below.
        .refreshable { dataStore.workoutHistoryDidChange() }
        // On the scroll view, not the start buttons: starting the workout
        // hides those buttons, and a sheet attached inside them would be
        // torn down mid-dismissal.
        .sheet(isPresented: $showsSessionBuilder, onDismiss: startBuiltWorkout) {
            SessionBuilderSheet { routine, linksRoutine in builtWorkout = (routine, linksRoutine) }
        }
        // `recordWorkoutFinished` bumps `dataStore.trainingRevision`
        // precisely so mounted views can recompute — before this listener
        // existed the overview kept serving pre-workout data after the
        // finish cover dismissed, until a pull-to-refresh or tab switch.
        // Keyed on the training revision, not `revision`, so a meal, dose
        // or profile edit doesn't re-run the all-time engines.
        // This one task also covers first appear: a second plain `.task`
        // ran every engine pass twice. `load()` is a no-op once loaded.
        .task(id: dataStore.trainingRevision) { @MainActor in
            await library.load()
            routineStore.load()
            refresh()
        }
        .onChange(of: selectedPeriod) { _, _ in
            AppAnimation.with(AppAnimation.springSmooth) { refreshFrequencies() }
        }
        .sheet(item: $inspectedMuscle) { muscle in
            MuscleHistorySheet(
                muscle: muscle,
                history: WeeklyMuscleHeatmap.history(
                    for: muscle, from: inspectedSessions, library: library, days: inspectedDays
                ),
                periodLabel: inspectedPeriodLabel,
                sessions: inspectedSessions
            )
        }
    }

    // MARK: - Trends & calendar

    private var trainingDetails: some View {
        VStack(spacing: Spacing.lg) {
            trainingDetailsHeader
            if showsTrainingDetails {
                VStack(spacing: Spacing.lg) {
                    MuscleGainsCard(
                        totals: totalFrequencies,
                        regularity: regularity,
                        onIdentify: { muscle, days in
                            inspectedDays = days
                            inspectedPeriodLabel = days == nil ? String(localized: "All workouts") : String(localized: "Last 12 calendar weeks")
                            inspectedMuscle = muscle
                        }
                    )
                    calendarCard
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: showsTrainingDetails)
    }

    /// Collapsible header on the same glass row as the cards around it,
    /// rather than a system `DisclosureGroup` that reads as a Settings row.
    private var trainingDetailsHeader: some View {
        Button {
            Haptics.selection()
            showsTrainingDetails.toggle()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "chart.bar.xaxis")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
                Text("Trends & calendar")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .rotationEffect(.degrees(showsTrainingDetails ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .frame(minHeight: Spacing.minimumHitTarget + Spacing.sm)
            .contentShape(Rectangle())
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityValue(showsTrainingDetails ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("training-trends-disclosure")
    }

    /// One painted action: start the routine that comes next in the
    /// rotation, or plan a workout when there's no routine yet. The other
    /// ways in sit under it as bare text, so the page has one primary.
    /// Before the first session "Empty workout" lives in the Quick start
    /// card instead, so the top holds at most two ways in.
    /// Hidden while a workout is in progress — the container's "Resume"
    /// banner is the action then.
    @ViewBuilder
    private var startWorkoutButton: some View {
        if sessionService.activeSession == nil {
            let nextRoutine = Self.suggestedRoutine(from: routineStore.routines, history: sessions)
            VStack(spacing: Spacing.sm) {
                if let nextRoutine {
                    PrimaryCTAButton(title: "Start \(nextRoutine.name)", icon: "play.fill", shape: .rounded) {
                        Haptics.impact(.medium)
                        routineStore.startWorkout(from: nextRoutine)
                    }
                    .accessibilityIdentifier("train-start-next-routine")
                } else {
                    planWorkoutCTA
                }
                let showsEmpty = !sessions.isEmpty
                let showsPlan = nextRoutine != nil
                if showsEmpty || showsPlan {
                    // Side by side only while both titles fit on one line each.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.xl) { otherStarts(showsEmpty: showsEmpty, showsPlan: showsPlan) }
                        VStack(spacing: Spacing.sm) { otherStarts(showsEmpty: showsEmpty, showsPlan: showsPlan) }
                    }
                }
            }
        }
    }

    private var planWorkoutCTA: some View {
        PrimaryCTAButton(title: "Plan a workout", icon: "wand.and.stars", shape: .rounded) {
            Haptics.impact(.medium)
            showsSessionBuilder = true
        }
        .accessibilityIdentifier("train-build-workout")
    }

    private func startBuiltWorkout() {
        guard let built = builtWorkout else { return }
        builtWorkout = nil
        sessionService.startWorkout(routine: built.routine, linksRoutine: built.linksRoutine)
    }

    /// Quiet starts under the painted one: accent text with no fill, so
    /// they read as alternatives rather than rivals to the primary.
    @ViewBuilder
    private func otherStarts(showsEmpty: Bool, showsPlan: Bool) -> some View {
        if showsEmpty {
            GlassButton(title: "Empty workout", icon: "play.circle", style: .ghost) {
                Haptics.impact(.medium)
                sessionService.startWorkout()
            }
        }
        if showsPlan {
            GlassButton(title: "Plan a workout", icon: "wand.and.stars", style: .ghost) {
                Haptics.impact(.medium)
                showsSessionBuilder = true
            }
            .accessibilityIdentifier("train-build-workout")
        }
    }

    /// The next routine in library order after the one trained most
    /// recently, wrapping round, so a Push / Pull / Legs rotation suggests
    /// Pull after Push. The first routine when none has been trained yet;
    /// routines with no exercises can't be started and are skipped.
    static func suggestedRoutine(from routines: [Routine], history: [WorkoutSession]) -> Routine? {
        let ready = routines.filter { !$0.exercises.isEmpty }
        guard let first = ready.first else { return nil }
        let readyIDs = Set(ready.map(\.id))
        let lastTrained = history
            .filter { session in session.routineID.map { readyIDs.contains($0) } ?? false }
            .max { $0.startedAt < $1.startedAt }
        guard let lastID = lastTrained?.routineID,
              let index = ready.firstIndex(where: { $0.id == lastID })
        else { return first }
        return ready[(index + 1) % ready.count]
    }

    // MARK: - This week

    /// Always shown, goal or not: an empty week draws outlined day marks
    /// rather than leaving the top of the tab blank.
    private var weekHero: some View {
        TrainWeekHeroCard(
            summary: weekSummary,
            target: (dataStore.profile.trainingPreferences?.daysPerWeek).flatMap { $0 > 0 ? $0 : nil },
            unit: unit
        )
    }

    /// Pulls the latest sessions out of SwiftData. Called on appear and
    /// whenever `dataStore.trainingRevision` bumps — which
    /// `recordWorkoutFinished` does on every workout finish, so the
    /// heatmap, recents, and calendar update live. The history itself is
    /// decoded once per revision, not on every appear.
    private func refresh() {
        allSessions = dataStore.finishedWorkoutHistory()
        sessions = Array(allSessions.prefix(SwiftDataRepository.workoutHistoryFetchLimit))
        refreshFrequencies()
        totalFrequencies = MuscleGainsEngine.totalFrequencies(
            from: allSessions,
            library: library
        )
        regularity = MuscleGainsEngine.weeklyRegularity(
            from: sessions,
            library: library
        )
        trainingContextCaption = Self.trainingContextCaption(for: sessions)
        weekSummary = TrainWeekSummary.make(from: sessions, calendar: .current)
    }

    /// Newest first, without the in-progress workout: a minimized
    /// session would otherwise show as the latest workout, mark today as
    /// trained and count toward the week before it's finished.
    static func finishedHistory(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter { !$0.isActive }.sorted { $0.startedAt > $1.startedAt }
    }

    private var inspectedSessions: [WorkoutSession] {
        inspectedDays == nil ? allSessions : sessions
    }

    private func refreshFrequencies() {
        frequencies = WeeklyMuscleHeatmap.frequencies(
            from: sessions, library: library, days: selectedPeriod.rawValue
        )
    }

    /// Builds the "how does this week compare" caption from the user's
    /// own session history. Returns `nil` whenever there isn't enough
    /// history to say anything personal (`TrainingPatternEngine` /
    /// `ChangeDetectionEngine` both refuse to produce a verdict below
    /// their own confidence floors) — the view simply omits the line
    /// rather than showing a hedge-free guess.
    private static func trainingContextCaption(for sessions: [WorkoutSession]) -> String? {
        let dates = sessions.map(\.dayAnchor)
        guard
            let baseline = TrainingPatternEngine.weeklyFrequencyBaseline(sessionDates: dates),
            baseline.confidence > .insufficientHistory
        else { return nil }

        // A rolling window, like the baseline it's compared to — so the
        // copy says "last 7 days", not "this week", which on Today and
        // Train's goal card means the calendar week's trained days.
        let thisWeek = TrainingPatternEngine.currentRollingWeekCount(sessionDates: dates)
        guard let result = ChangeDetectionEngine.evaluate(current: Double(thisWeek), against: baseline)
        else { return nil }

        let tail: String
        switch result.change {
        case .stable:
            tail = String(localized: "right in line with your usual pace")
        case .notablyHigher:
            tail = String(localized: "more than your usual pace")
        case .notablyLower:
            tail = String(localized: "fewer than your usual pace")
        case .unusual:
            tail = Double(thisWeek) > baseline.mean ? String(localized: "well above your usual pace") : String(localized: "well below your usual pace")
        }

        // Emerging confidence still gets to speak personally (Phase 3
        // says hedge, not stay silent) — just flagged as an early read
        // rather than stated as flatly as an established baseline would be.
        let prefix = baseline.confidence == .emergingBaseline ? String(localized: "Early read: ") : ""
        return String(localized: "\(prefix)\(thisWeek) sessions in the last 7 days — \(tail).")
    }

    // MARK: - Weekly muscle map

    private var weeklyMuscleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        // Same weight as the other card titles on this tab; a
                        // display-size title here out-shouted the CTA above.
                        Text("Muscles trained")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(weekHasTraining
                             ? "Completed working sets · \(selectedPeriod.detail.lowercased())"
                             : "Log a workout and watch your body light up.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if weekHasTraining {
                        HStack(spacing: Spacing.sm) {
                            BodyFacingButton(facing: $bodyFacing)
                            mapInfoButton
                        }
                    }
                }

                GlassSegmentedControl(
                    options: TrainingMapPeriod.allCases,
                    selected: Binding(get: { selectedPeriod }, set: { selectedPeriodRaw = $0.rawValue }),
                    label: { LocalizedStringKey($0.title) }
                )
                .accessibilityIdentifier("training-map-period")

                TrainingBodyExplorer(
                    highlights: MuscleMapView.intensityHighlights(from: frequencies),
                    side: $bodyFacing,
                    legend: .intensity(low: String(localized: "Less"), high: String(localized: "Most")),
                    onIdentify: { inspectRecentMuscle($0) }
                )
                .frame(maxWidth: .infinity)

                if selectedPeriod == .week, let trainingContextCaption {
                    Text(trainingContextCaption)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    /// The how-to and the scoring note, on demand instead of two
    /// permanent paragraphs under the map.
    private var mapInfoButton: some View {
        Button {
            showsMapInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About this map")
        .popover(isPresented: $showsMapInfo) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Tap the arrows to see the front or back up close. Tap a muscle for its exercises.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Relative training score: primary work counts more than supporting work. Not a measure of growth or recovery.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(idealWidth: 300)
            .padding(Spacing.lg)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func inspectRecentMuscle(_ muscle: AnatomicalMuscle) {
        inspectedDays = selectedPeriod.rawValue
        inspectedPeriodLabel = selectedPeriod.detail
        inspectedMuscle = muscle
    }

    // MARK: - Recent workouts

    private var latestWorkoutTitle: some View {
        Text("Latest workout")
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textPrimary)
    }

    private var viewAllWorkoutsLink: some View {
        NavigationLink(value: TrainNavigation.workoutHistory) {
            Text("View all").font(AppFont.subheadline).minimumHitArea()
        }
        .accessibilityLabel("View workout history")
    }

    private var recentWorkoutsCard: some View {
        GlassCard {
            if sessions.isEmpty {
                quickStartCard
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    latestWorkoutHeader
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(1))) { session in
                            recentWorkoutRow(session)
                        }
                    }
                }
            }
        }
    }

    /// Title and link share a row while both fit whole; at the largest
    /// text sizes the link moves under the title rather than hyphenating
    /// it into three lines.
    private var latestWorkoutHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                latestWorkoutTitle
                Spacer()
                viewAllWorkoutsLink
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                latestWorkoutTitle
                viewAllWorkoutsLink
            }
        }
    }

    // MARK: - Quick start

    /// Before the first session there's nothing to look back on, so the
    /// card offers a first workout instead: the user's own routines when
    /// they have more than the one the primary button starts, else the
    /// bundled starters. Each row starts in one
    /// tap; a starter runs unsaved, so trying one doesn't add a routine.
    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Quick start")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Spacing.sm) {
                ForEach(quickStartRoutines) { routine in
                    quickStartRow(routine)
                }
                emptyWorkoutRow
            }
        }
    }

    private var quickStartRoutines: [Routine] {
        // Without the routine the primary button already offers.
        let suggested = Self.suggestedRoutine(from: routineStore.routines, history: sessions)?.id
        let own = routineStore.routines.filter { !$0.exercises.isEmpty && $0.id != suggested }
        guard own.isEmpty else { return Array(own.prefix(Self.quickStartCount)) }
        return Self.starterRoutines
    }

    private static let quickStartCount = 3

    /// Built once: fresh ids per render would rebuild every row.
    private static let starterRoutines: [Routine] = RoutineTemplate.starters
        .prefix(quickStartCount)
        .map { Routine(name: $0.name, subtitle: $0.summary, exercises: $0.makeExercises()) }

    private func quickStartDetail(_ routine: Routine) -> Text {
        let count = routine.exercises.count
        guard let subtitle = routine.subtitle, !subtitle.isEmpty else {
            return Text("^[\(count) exercise](inflect: true)")
        }
        return Text("\(subtitle) · ^[\(count) exercise](inflect: true)")
    }

    private func quickStartRow(_ routine: Routine) -> some View {
        let isSaved = routineStore.routines.contains { $0.id == routine.id }
        return quickStartButton(
            title: Text(routine.name),
            detail: quickStartDetail(routine),
            label: Text("Start \(routine.name)")
        ) {
            sessionService.startWorkout(routine: routine, linksRoutine: isSaved)
        }
    }

    /// Last in the list, so the blank start is still one tap away without
    /// a third button competing with "Plan a workout" up top. Labelled
    /// "Empty workout" like the button it replaces, which UI tests tap.
    private var emptyWorkoutRow: some View {
        quickStartButton(
            title: Text("Empty workout"),
            detail: Text("Add exercises as you go"),
            label: Text("Empty workout")
        ) {
            sessionService.startWorkout()
        }
    }

    private func quickStartButton(
        title: Text, detail: Text, label: Text, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    title
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    detail
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "play.fill")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .frame(minHeight: Spacing.minimumHitTarget)
            .insetRowBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    /// A recent-session row, now a real NavigationLink into
    /// `WorkoutSessionDetailView` (the container already declares the
    /// `TrainNavigation.workoutDetail` destination). The header comment
    /// promised rows "tappable into the (future) detail view" — the
    /// detail view shipped, the tap never did.
    private func recentWorkoutRow(_ session: WorkoutSession) -> some View {
        NavigationLink(value: TrainNavigation.workoutDetail(session.id)) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(session.displayName)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text("^[\(session.completedSetCount) set](inflect: true)")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    if session.totalVolumeKg > 0 {
                        Text(unit.weightLabel(session.totalVolumeKg))
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .monospacedDigit()
                    }
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            // A full tap target without padding: vertical padding here sat
            // on top of the card's own, leaving 24pt under the row and 16pt
            // above the title.
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(currentMonthLabel)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                }
                TrainingCalendarGrid(sessions: sessions)
            }
        }
    }

    private var currentMonthLabel: String {
        Date().formatted(.dateTime.month(.wide).year()).capitalized
    }

    // MARK: - Display helpers

}

// MARK: - Calendar grid

/// Calendar grid for the current month — one cell per day, tinted by
/// whether the user trained that day. Visually echoes the existing
/// peptide compliance calendar so the two surfaces feel like
/// siblings.
struct TrainingCalendarGrid: View {
    let sessions: [WorkoutSession]
    /// Scales with Dynamic Type so the day numbers don't clip.
    @ScaledMetric private var cellHeight: CGFloat = 28

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        // Built once per render, not once per day cell.
        let trainedDays = Set(sessions.map { $0.day(in: cal) })
        guard let monthInterval = cal.dateInterval(of: .month, for: now),
              let firstDayWeekday = cal.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return AnyView(EmptyView()) }

        // Calendar.range returns nil for invalid components, and in
        // pathological cases could theoretically return an empty
        // range — guard before building `1...daysInMonth` so a
        // ClosedRange trap can't fire under any locale / time zone.
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        guard daysInMonth > 0 else { return AnyView(EmptyView()) }
        // Honor the user's calendar (`firstWeekday`): US starts on Sunday,
        // UK / Germany on Monday, Saudi on Saturday. Previously a Monday
        // pivot was hardcoded which left a leading-blank shift on
        // Sunday-first locales (audit Train M2).
        let leadingBlanks = (firstDayWeekday - cal.firstWeekday + 7) % 7

        return AnyView(
            VStack(spacing: Spacing.xs) {
                weekdayHeaderRow(calendar: cal)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                          spacing: 6) {
                    ForEach(0..<leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(height: cellHeight)
                    }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        dayCell(for: day, monthStart: monthInterval.start, calendar: cal, trainedDays: trainedDays)
                    }
                }
            }
        )
    }

    private func weekdayHeaderRow(calendar: Calendar) -> some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        let rotated = Array(symbols[offset...]) + Array(symbols[..<offset])
        return HStack(spacing: 6) {
            ForEach(Array(rotated.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(for day: Int, monthStart: Date, calendar: Calendar, trainedDays: Set<Date>) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        let trained = trainedDays.contains(calendar.startOfDay(for: date))
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        return Text("\(day)")
            .font(AppFont.caption2)
            .foregroundStyle(textColor(trained: trained, isToday: isToday, isFuture: isFuture))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .fill(backgroundColor(trained: trained, isToday: isToday))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .stroke(isToday ? AppColor.accentPrimary : Color.clear, lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date.formatted(.dateTime.month().day()))
            .accessibilityValue(trained ? "Trained" : "")
    }

    private func textColor(trained: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isFuture { return AppColor.textTertiary }
        if trained { return AppColor.onAccent }
        if isToday { return AppColor.accentPrimary }
        return AppColor.textSecondary
    }

    private func backgroundColor(trained: Bool, isToday: Bool) -> Color {
        if trained { return AppColor.accentFill }
        return Color.clear
    }
}

#Preview {
    TrainOverviewView(scrollPosition: .constant(ScrollPosition(edge: .top)))
        .environment(DataStore(seedSampleData: true))
        .padding(.top, Spacing.lg)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
