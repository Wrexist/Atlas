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
    @Environment(DataStore.self) private var dataStore
    @State private var library = ExerciseLibrary.shared
    @State private var sessions: [WorkoutSession] = []
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

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    private var weekHasTraining: Bool {
        !frequencies.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                startWorkoutButton
                weeklyMuscleCard
                if weekHasTraining {
                    topMusclesRow
                }
                MuscleGainsCard(
                    totals: totalFrequencies,
                    regularity: regularity,
                    onIdentify: { inspectedMuscle = $0 }
                )
                recentWorkoutsCard
                calendarCard
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
        }
        .refreshable { refresh() }
        .task { @MainActor in
            await library.load()
            refresh()
        }
        // `recordWorkoutFinished` bumps `dataStore.revision` precisely
        // so mounted views can recompute — before this listener existed
        // the overview kept serving pre-workout data after the finish
        // cover dismissed, until a pull-to-refresh or tab switch
        // (audit Train P2; the refresh() doc used to promise a
        // notification "next commit" that never landed).
        .task(id: dataStore.revision) { @MainActor in
            refresh()
        }
        .sheet(item: $inspectedMuscle) { muscle in
            MuscleHistorySheet(
                muscle: muscle,
                history: WeeklyMuscleHeatmap.history(
                    for: muscle, from: sessions, library: library
                )
            )
        }
    }

    /// Primary CTA — kicks off an empty workout. Hidden when one's
    /// already in progress (the container surfaces a "Resume" banner
    /// in that case so we don't show two competing actions).
    @ViewBuilder
    private var startWorkoutButton: some View {
        if sessionService.activeSession == nil {
            PrimaryCTAButton(title: "Start workout", icon: "play.fill", shape: .rounded) {
                sessionService.startWorkout()
            }
        }
    }

    /// Pulls the latest sessions out of SwiftData. Called on appear,
    /// on pull-to-refresh, and whenever `dataStore.revision` bumps —
    /// which `recordWorkoutFinished` does on every workout finish, so
    /// the heatmap, recents, and calendar update live.
    private func refresh() {
        sessions = SwiftDataRepository.shared.loadWorkoutSessions()
        frequencies = WeeklyMuscleHeatmap.frequencies(
            from: sessions,
            library: library
        )
        totalFrequencies = MuscleGainsEngine.totalFrequencies(
            from: sessions,
            library: library
        )
        regularity = MuscleGainsEngine.weeklyRegularity(
            from: sessions,
            library: library
        )
    }

    // MARK: - Weekly muscle map

    private var weeklyMuscleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week")
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(weekHasTraining
                             ? "Muscles you trained over the past 7 days."
                             : "Log a workout and watch your body light up.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    NavigationLink(value: TrainNavigation.workoutHistory) {
                        Image(systemName: "calendar")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Workout history")
                }

                MuscleMapView(
                    highlights: MuscleMapView.intensityHighlights(from: frequencies),
                    onIdentify: { inspectedMuscle = $0 }
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 320)
                .animation(AppAnimation.fadeInSlow, value: frequencies)

                // Both of these describe heat that isn't there yet on a
                // fresh install, where the subtitle above is already
                // carrying the message.
                if weekHasTraining {
                    Text("Tap a muscle to see what you've trained it with.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                    intensityLegend
                }
            }
        }
    }

    /// Tells the user what the heatmap colours mean — green = trained a
    /// little this week, climbing through yellow, orange and red to
    /// purple for the most-trained muscle — so the figure isn't a
    /// mystery on first glance.
    private var intensityLegend: some View {
        MuscleHeatLegend(lowLabel: "Less", highLabel: "Most")
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
        let setCount = Int(count.rounded())
        return VStack(spacing: 4) {
            Text(muscle.displayName)
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
            Text("\(setCount) \(setCount == 1 ? "set" : "sets")")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Recent workouts

    private var recentWorkoutsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Recent workouts")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !sessions.isEmpty {
                        Text("\(sessions.count) total")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                if sessions.isEmpty {
                    emptyRecentWorkouts
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(3))) { session in
                            recentWorkoutRow(session)
                            if session.id != sessions.prefix(3).last?.id {
                                Divider().background(AppColor.glassBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyRecentWorkouts: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No sessions yet")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
            Text("Browse the Exercises tab and log your first set — it'll show up here.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.vertical, Spacing.sm)
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
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(session.completedSetCount) sets")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    if session.totalVolumeKg > 0 {
                        Text(unit.weightLabel(session.totalVolumeKg))
                            .font(AppFont.caption)
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
        return "\(dayName) workout"
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date()).capitalized
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

    private var trainedDays: Set<Date> {
        let cal = Calendar.current
        return Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
    }

    var body: some View {
        let cal = Calendar.current
        let now = Date()
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
                        Color.clear.frame(height: 28)
                    }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        dayCell(for: day, monthStart: monthInterval.start, calendar: cal)
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
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(for day: Int, monthStart: Date, calendar: Calendar) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        let trained = trainedDays.contains(calendar.startOfDay(for: date))
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        return Text("\(day)")
            .font(AppFont.caption)
            .foregroundStyle(textColor(trained: trained, isToday: isToday, isFuture: isFuture))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .fill(backgroundColor(trained: trained, isToday: isToday))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .stroke(isToday ? AppColor.accentPrimary : Color.clear, lineWidth: 1)
            )
    }

    private func textColor(trained: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isFuture { return AppColor.textTertiary.opacity(0.6) }
        if trained { return AppColor.background }
        if isToday { return AppColor.accentPrimary }
        return AppColor.textSecondary
    }

    private func backgroundColor(trained: Bool, isToday: Bool) -> Color {
        if trained { return AppColor.accentPrimary }
        return Color.clear
    }
}

#Preview {
    TrainOverviewView()
        .environment(DataStore(seedSampleData: true))
        .padding(.top, Spacing.lg)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
