import SwiftUI

/// Train tab landing surface — "Översikt" in the Lyfta reference.
/// Built around three layered cards:
///
///   1. **Weekly muscle map** — anatomical figure that lights up the
///      muscles the user actually trained over the past 7 days. The
///      whole body stays visible at a low baseline so the surface
///      reads even on a fresh install.
///   2. **Top muscles** — three pills under the map calling out the
///      most-worked regions, with the working-set count.
///   3. **Recent workouts** — the last three sessions with date, set
///      count and total volume, tappable into the (future) detail
///      view.
///   4. **Month calendar** — heat-by-day grid for the current month.
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
    /// Memoised result of `WeeklyMuscleHeatmap.frequencies` — the
    /// underlying scan is O(sessions × exercises × muscles) and was
    /// previously recomputed on every body re-evaluation because the
    /// `weekHasTraining` and `weeklyMuscleCard`/`topMusclesRow` paths
    /// both touched the computed property. Recomputed only when
    /// `refresh()` runs (i.e. when sessions actually change).
    @State private var frequencies: [AnatomicalMuscle: Double] = [:]
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

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                startWorkoutButton
                    .sectionAppear(index: 0)
                recentWorkoutsCard
                    .sectionAppear(index: 1)
                weeklyMuscleCard
                    .sectionAppear(index: 2)
                if weekHasTraining {
                    topMusclesRow
                        .sectionAppear(index: 3)
                }
                trainingDetails
                    .scrollReveal()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .scrollPosition($scrollPosition)
        .refreshable { refresh() }
        // `recordWorkoutFinished` bumps `dataStore.revision` precisely
        // so mounted views can recompute — before this listener existed
        // the overview kept serving pre-workout data after the finish
        // cover dismissed, until a pull-to-refresh or tab switch.
        // This one task also covers first appear: a second plain `.task`
        // ran every engine pass twice. `load()` is a no-op once loaded.
        .task(id: dataStore.revision) { @MainActor in
            await library.load()
            refresh()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Haptics.selection()
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

    /// Primary CTA — kicks off an empty workout. Hidden when one's
    /// already in progress (the container surfaces a "Resume" banner
    /// in that case so we don't show two competing actions).
    @ViewBuilder
    private var startWorkoutButton: some View {
        if sessionService.activeSession == nil {
            PrimaryCTAButton(title: "Start workout", icon: "play.fill", shape: .rounded) {
                Haptics.impact(.medium)
                sessionService.startWorkout()
            }
        }
    }

    /// Pulls the latest sessions out of SwiftData. Called on appear,
    /// on pull-to-refresh, and whenever `dataStore.revision` bumps —
    /// which `recordWorkoutFinished` does on every workout finish, so
    /// the heatmap, recents, and calendar update live.
    private func refresh() {
        allSessions = Self.finishedHistory(SwiftDataRepository.shared.loadAllWorkoutSessions())
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
        let dates = sessions.map(\.startedAt)
        guard
            let baseline = TrainingPatternEngine.weeklyFrequencyBaseline(sessionDates: dates),
            baseline.confidence > .insufficientHistory
        else { return nil }

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
        return String(localized: "\(prefix)\(thisWeek) sessions this week — \(tail).")
    }

    // MARK: - Weekly muscle map

    private var weeklyMuscleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Muscles trained")
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(weekHasTraining
                             ? "Completed working sets · \(selectedPeriod.detail.lowercased())"
                             : "Log a workout and watch your body light up.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if weekHasTraining {
                        mapInfoButton
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
                Text("Select Front or Back for a closer look. Tap a muscle for its exercises.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Relative training score: primary work counts more than secondary work. Not a measure of growth or recovery.")
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

    // MARK: - Top muscles row

    private var topMusclesRow: some View {
        let top = topMuscleGroups()
        return HStack(spacing: Spacing.sm) {
            ForEach(top, id: \.muscle) { item in
                topMusclePill(for: item.muscle, count: item.count)
            }
            Spacer(minLength: 0)
        }
    }

    /// Collapse the per-head frequency map into per-group totals — so the
    /// row shows one "Quads" pill summing all three heads rather than three
    /// identical pills — and return the three most-trained groups.
    private func topMuscleGroups() -> [(muscle: AnatomicalMuscle, count: Double)] {
        var byGroup: [String: (muscle: AnatomicalMuscle, count: Double)] = [:]
        for (muscle, count) in frequencies {
            if let existing = byGroup[muscle.displayName] {
                byGroup[muscle.displayName] = (existing.muscle, existing.count + count)
            } else {
                byGroup[muscle.displayName] = (muscle, count)
            }
        }
        return byGroup.values
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count
                                       : lhs.muscle.displayName < rhs.muscle.displayName
            }
            .prefix(3)
            .map { (muscle: $0.muscle, count: $0.count) }
    }

    private func topMusclePill(for muscle: AnatomicalMuscle, count: Double) -> some View {
        let score = Int(count.rounded())
        return Button {
            inspectRecentMuscle(muscle)
        } label: {
            VStack(spacing: Spacing.xs) {
                Text(muscle.displayName)
                    .font(AppFont.chipText)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Score \(score)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the exercises you logged for this muscle")
    }

    // MARK: - Recent workouts

    private var recentWorkoutsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Latest workout")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !sessions.isEmpty {
                        NavigationLink(value: TrainNavigation.workoutHistory) {
                            Text("View all").font(AppFont.subheadline).minimumHitArea()
                        }
                        .accessibilityLabel("View workout history")
                    }
                }

                if sessions.isEmpty {
                    emptyRecentWorkouts
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(1))) { session in
                            recentWorkoutRow(session)
                        }
                    }
                }
            }
        }
    }

    private var emptyRecentWorkouts: some View {
        // No action button: Start workout sits directly above this card.
        EmptyStateView(
            icon: "dumbbell",
            title: "No sessions yet",
            message: "Start a workout or pick a routine — it'll land here.",
            style: .compact
        )
    }

    /// A recent-session row, now a real NavigationLink into
    /// `WorkoutSessionDetailView` (the container already declares the
    /// `TrainNavigation.workoutDetail` destination). The header comment
    /// promised rows "tappable into the (future) detail view" — the
    /// detail view shipped, the tap never did.
    private func recentWorkoutRow(_ session: WorkoutSession) -> some View {
        NavigationLink(value: TrainNavigation.workoutDetail(session.id)) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name ?? defaultSessionName(for: session))
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
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
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func defaultSessionName(for session: WorkoutSession) -> String {
        let dayName = session.startedAt.formatted(.dateTime.weekday(.wide))
        return String(localized: "\(dayName) workout")
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
        let trainedDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
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
