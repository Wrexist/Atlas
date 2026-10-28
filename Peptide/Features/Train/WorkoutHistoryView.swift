import SwiftUI

/// Real history list — replaces the hardcoded "No workouts logged
/// yet" placeholder that persisted forever even after 30 finished
/// workouts (audit Train C2). Reads from SwiftDataRepository and
/// groups by month so the user can scan through their year.
struct WorkoutHistoryView: View {
    @State private var groupedSessions: [MonthGroup] = []
    @State private var hasLoaded: Bool = false
    /// Grows a page at a time so long-time users can reach older months
    /// without the first open decoding years of sessions.
    @State private var fetchLimit = SwiftDataRepository.workoutHistoryFetchLimit
    @State private var hasOlderSessions = false
    @State private var sessionService = WorkoutSessionService.shared
    /// Workouts other apps saved to Apple Health, newest first. Empty
    /// unless Health is connected on this device.
    @State private var cardio: [ImportedCardioWorkout] = []
    /// Health was connected before workouts joined the read types, so
    /// the user hasn't been asked for them yet.
    @State private var needsWorkoutAccess = false
    @State private var inspectedCardio: ImportedCardioWorkout?
    @Environment(DataStore.self) private var dataStore
    @ScaledMetric(relativeTo: .headline) private var activityIconWidth: CGFloat = 28

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    /// Explicit type rather than a `.init` shorthand inside the call —
    /// leading-dot syntax in an optional-typed ternary is the kind of
    /// inference that reads fine and resolves badly.
    private var startAction: EmptyStateView.Action? {
        guard sessionService.activeSession == nil else { return nil }
        return EmptyStateView.Action(title: "Start a workout", icon: "play.fill") {
            sessionService.startWorkout()
        }
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupedSessions.isEmpty && cardio.isEmpty && !needsWorkoutAccess {
                EmptyStateView(
                    icon: "calendar",
                    title: "No workouts logged yet",
                    message: "Once you finish your first session, it'll show up here, grouped by month.",
                    // TrainContainerView presents the active workout as soon
                    // as `activeSession` appears, so starting one here needs
                    // no plumbing back through the parent.
                    action: startAction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .onAppear(perform: reload)
        // A workout finished or edited elsewhere bumps the revision.
        .onChange(of: dataStore.revision) { _, _ in reload() }
        .task(id: dataStore.profile.healthConnected) { await loadCardio() }
        .sheet(item: $inspectedCardio) { workout in
            CardioWorkoutDetailSheet(workout: workout, unit: unit)
        }
    }

    /// Always hosted inside TrainContainerView's `NavigationStack`, so it
    /// pushes through that stack's `TrainNavigation` destinations rather
    /// than nesting a stack of its own.
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                if !cardio.isEmpty || needsWorkoutAccess {
                    cardioSection
                }
                ForEach(groupedSessions, id: \.month) { group in
                    Section {
                        VStack(spacing: Spacing.sm) {
                            ForEach(group.sessions) { session in
                                NavigationLink(value: TrainNavigation.workoutDetail(session.id)) {
                                    row(for: session)
                                }
                                .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                            }
                        }
                    } header: {
                        sectionHeader(
                            group.month.formatted(.dateTime.month(.wide).year()),
                            detail: Text("^[\(group.sessions.count) workout](inflect: true)")
                        )
                    }
                }
                if hasOlderSessions {
                    GlassButton(title: "Load older workouts", icon: "clock.arrow.circlepath", style: .secondary) {
                        fetchLimit += SwiftDataRepository.workoutHistoryFetchLimit
                        reload()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    /// The month's workout count sits beside its name, so a long history
    /// scans as a tally per month rather than an unbroken list.
    private func sectionHeader(_ label: String, detail: Text?) -> some View {
        HStack {
            Text(label)
                .font(AppFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            if let detail {
                detail
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .background(AppColor.background)
    }

    private func row(for session: WorkoutSession) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(session.displayDate)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                Text(session.displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(summaryLine(for: session))
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if let duration = session.durationLabel {
                Label(duration, systemImage: "clock")
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .contentShape(Rectangle())
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Apple Health workouts

    /// Runs, rides and walks other apps recorded, above Atlas's own
    /// sessions, with this week's total minutes in the header.
    private var cardioSection: some View {
        Section {
            VStack(spacing: Spacing.sm) {
                if needsWorkoutAccess {
                    GlassEntryRow(
                        icon: "figure.run",
                        title: "Show workouts from Apple Health",
                        subtitle: Text("Runs, rides and walks from your Apple Watch or other apps"),
                        action: requestWorkoutAccess
                    )
                    .accessibilityHint("Asks Apple Health for access to workouts")
                }
                ForEach(cardio) { workout in
                    Button {
                        inspectedCardio = workout
                    } label: {
                        cardioRow(for: workout)
                    }
                    .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                }
            }
        } header: {
            sectionHeader(
                String(localized: "From Apple Health"),
                detail: cardio.isEmpty ? nil : Text("\(CardioWorkoutEngine.minutesThisWeek(cardio)) min this week")
            )
        }
    }

    private func cardioRow(for workout: ImportedCardioWorkout) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: workout.activity.symbol)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: activityIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workout.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                Text(workout.activity.name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(CardioWorkoutEngine.summary(of: workout, unit: unit))
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Label(CardioWorkoutEngine.durationLabel(workout.duration), systemImage: "clock")
                .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .contentShape(Rectangle())
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }

    /// Reads only while Health is connected here, so a user who never
    /// connected sees nothing new.
    private func loadCardio() async {
        let health = HealthKitService.shared
        guard dataStore.profile.healthConnected, health.isAvailable else {
            cardio = []
            needsWorkoutAccess = false
            return
        }
        needsWorkoutAccess = await health.hasUnrequestedWorkoutReadTypes()
        cardio = await health.externalWorkouts(days: CardioWorkoutEngine.historyWindowDays)
    }

    private func requestWorkoutAccess() {
        Task {
            _ = await HealthKitService.shared.requestAuthorization()
            await loadCardio()
        }
    }

    private func summaryLine(for session: WorkoutSession) -> String {
        let exercises = session.exercises.count == 1
            ? String(localized: "1 exercise")
            : String(localized: "\(session.exercises.count) exercises")
        let sets = session.completedSetCount == 1
            ? String(localized: "1 set")
            : String(localized: "\(session.completedSetCount) sets")
        guard session.totalVolumeKg > 0 else { return "\(exercises) · \(sets)" }
        return "\(exercises) · \(sets) · \(unit.weightLabel(session.totalVolumeKg))"
    }

    // MARK: - Grouping

    private struct MonthGroup: Hashable {
        /// Start of the calendar month.
        let month: Date
        var sessions: [WorkoutSession]
    }

    /// Newest month first, newest session first within each month.
    private static func group(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> [MonthGroup] {
        let sorted = sessions.sorted { $0.historyDate > $1.historyDate }
        var groups: [MonthGroup] = []
        for session in sorted {
            let month = calendar.dateInterval(of: .month, for: session.historyDate)?.start ?? session.historyDate
            if groups.last?.month == month {
                groups[groups.count - 1].sessions.append(session)
            } else {
                groups.append(MonthGroup(month: month, sessions: [session]))
            }
        }
        return groups
    }

    private func reload() {
        let loaded = SwiftDataRepository.shared.loadWorkoutSessions(limit: fetchLimit)
        hasOlderSessions = loaded.count >= fetchLimit
        groupedSessions = Self.group(loaded.filter { $0.finishedAt != nil })
        hasLoaded = true
    }
}

private extension WorkoutSession {
    var historyDate: Date { finishedAt ?? startedAt }

    /// "Mon, Aug 12" in the user's locale — the row header.
    var displayDate: String {
        historyDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// The recap's duration, so history, detail and recap agree. Nil when
    /// the workout's time wasn't tracked or can't be trusted.
    var durationLabel: String? {
        let duration = WorkoutRecapEngine.duration(of: self)
        guard case .tracked = duration else { return nil }
        return duration.label
    }
}
