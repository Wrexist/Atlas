import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var selectedEntry: ProtocolEntry?
    @State private var achievementService = AchievementService.shared
    @State private var showProgress = false
    /// Observed directly so the notification banner reacts to a fresh
    /// schedule report. DataStore exposes `notificationReport` as a passthrough,
    /// but a computed read from a non-observed singleton wouldn't re-render
    /// the View on its own.
    @State private var notificationService = NotificationService.shared
    /// Drives the calorie/macro targets editor presented from the
    /// Today overview card's "Set a calorie target" nudge — previously
    /// the nudge was tappable but wired to nothing.
    @State private var showTargetsEditor = false
    @State private var showResearchAssistant = false
    @State private var showEditToday = false
    // Profile is opened via the shared `appState.showProfile` flag now
    // (a single app-level sheet), so the Today avatar and every other
    // tab's avatar button route through the same presentation.
    /// 0…1 fade progress for the sticky compressing header. Driven
    /// by `.onScrollGeometryChange` so the bar materialises in lock-
    /// step with the user's finger. Handed down as a binding and never
    /// read here, so scroll frames re-render only the header.
    @State private var stickyProgress: Double = 0
    /// State of the Sunday-recap card on Today. Loads on the first
    /// appear of each weekend; cached entries pre-fill the .ready
    /// branch so re-appears don't refire the network call.
    @State private var weeklySummaryState: WeeklySummaryHeroCard.State?
    /// Set when the user taps the Today recap card; drives the
    /// navigation push into the detail view.
    @State private var detailWeekStart: String?
    /// Rule-based weekly check-in, shown under the recap on Sundays and
    /// Mondays and inside the current week's recap. Rebuilt with the
    /// derived models; `checkInSleep` is the Health part, fetched apart.
    @State private var weeklyCheckIn: WeeklyCheckIn?
    @State private var checkInSleep: [(date: Date, value: Double)] = []
    /// Cycle-milestone prompt state. Both are nil unless the
    /// CycleMilestoneService has surfaced a pending (protocol,
    /// milestone) pair on appear; the prompt sheet routes into the
    /// share preview by setting `milestoneShareProtocol`, which drives
    /// a separate `.sheet(item:)` so SwiftUI cleanly chains the two
    /// modals across runloop ticks.
    @State private var milestonePrompt: MilestonePromptItem?
    @State private var milestoneShareProtocol: PeptideProtocol?
    /// Drives the cycle-completion sheet (Plan A). Set when a user's
    /// active protocol has passed its cycle end and they haven't
    /// already dismissed past the threshold. Cleared via the four
    /// onResolve callbacks (mark / extend / new / dismiss).
    @State private var completionPrompt: CompletionPromptItem?
    /// Set by the three resolving actions so the sheet's disappear
    /// handler can count every other exit — "Decide later" or a
    /// swipe-down — as a dismissal toward auto-completion.
    @State private var completionPromptResolved = false
    /// Tracks which jump-bar section is currently nearest the top of
    /// the viewport so the corresponding chip highlights. Driven by
    /// per-section preference reads in `.onScrollGeometryChange` —
    /// effectively free since the scroll geometry callback is already
    /// firing for the sticky-header progress.
    @State private var activeJumpAnchor: TodayJumpBar.SectionAnchor?
    /// The chip the user just tapped. Holds the highlight while the jump
    /// scroll animates past other sections, until the user scrolls again.
    @State private var pendingJumpAnchor: TodayJumpBar.SectionAnchor?
    /// Routes the chip-bar "+ Log" button. The sheet flag controls
    /// the picker; the action enum drives which sheet actually mounts.
    @State private var showQuickLogSheet = false
    @State private var quickLogAction: QuickLogAction?
    @State private var showWeightSheet = false
    @State private var showSupplements = false
    /// Bevel-style hero metric trio snapshot. Loaded async on first
    /// appear + on each .active scene transition so the rings reflect
    /// the freshest HealthKit reads without blocking the view body.
    @State private var heroSnapshot: HeroMetricSnapshot = .empty
    /// True until the first `refreshHeroSnapshot()` lands, so the trio
    /// shows a skeleton instead of flashing "—" rings before real values.
    @State private var isHeroLoading = true
    /// Session-only dismissal of the reminder-limit banner. Cleared when
    /// a reschedule drops a different set of protocols, so a new problem
    /// isn't hidden behind the old dismissal.
    @State private var notificationBannerDismissed = false
    /// Health Monitor grid snapshot — HRV / RHR / Sleep with their
    /// personal-range envelopes. Same refresh cadence as the hero
    /// trio so a freshly-synced HealthKit write updates both at once.
    @State private var healthRange: HealthRangeService.Snapshot = .init(hrv: nil, rhr: nil, sleep: nil)
    /// Drives the Bevel-style "Sync Complete" toast. Set true after
    /// each successful refresh of the hero + health-range snapshots
    /// so the user gets visible confirmation the dashboard is fresh.
    @State private var showSyncToast = false
    /// The first successful range build of a HomeView only fills an
    /// empty snapshot — that's a launch, not a sync worth announcing.
    @State private var hasLoadedHealthRange = false
    /// Health's daily step buckets, wide enough to cover the shown day.
    /// Steps move without any store mutation, so they're fetched here
    /// and folded into the checklist rather than read from `DataStore`.
    @State private var stepBuckets: [(date: Date, value: Double)] = []
    /// The last one-tap water glass, kept so its toast can undo it.
    @State private var lastWaterLog: WaterLog?
    @State private var showWaterToast = false
    @State private var waterToastMessage: LocalizedStringResource = ""
    @State private var waterToastID = 0
    /// Identifies which hero-trio ring the user tapped so the
    /// detail sheet can route. Non-optional Identifiable wrapper so
    /// `.sheet(item:)` does the right thing.
    @State private var heroDetailKind: HeroDetailItem?
    /// Everything Today derives from the store. These four used to be
    /// computed properties read straight from `body`, which meant a SwiftData
    /// fetch (the timeline), a `NumberFormatter` allocation plus a cold
    /// insight recompute (the overview), and two engine passes ran on *every*
    /// render — including every frame of a scroll, since `body` re-evaluates
    /// on any `DataStore` mutation. `refreshDerived()` computes them once per
    /// `dataStore.revision` change instead.
    @State private var derived = DerivedToday()
    /// Day Today is showing, as an offset from today (0 = today) — the
    /// model `MealDaySwitcher` speaks, so the screen still means "today"
    /// after midnight and never reaches into the future.
    @State private var dayOffset = 0
    @State private var summaryService = OnDeviceSummaryService.shared
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    /// What `refreshDerived()` reruns on: any store mutation, or a
    /// different day picked in the switcher.
    private struct DerivedKey: Equatable {
        let revision: Int
        let dayOffset: Int
    }

    private struct StepsKey: Equatable {
        let dayOffset: Int
        let healthConnected: Bool
    }

    /// Everything here describes the shown day, except `primaryReason`
    /// and `workoutsThisWeek`, which are about now and only render today.
    private struct DerivedToday {
        var overview: TodayOverviewSnapshot?
        var plan: DailyScheduleEngine.DailyPlan?
        var timeline: [TodayTimelineEvent] = []
        /// The single top-of-Today reason to act, reconciled by
        /// `PrimaryReasonEngine` from coaching, today's dose plan, habits
        /// due, and a freshly-changed weekly review. Replaces the old
        /// `coaching` field — every one of its call sites just wanted the
        /// message that would be shown, so `CoachingCard` now renders
        /// `primaryReason?.message` instead.
        var primaryReason: PrimaryReasonEngine.Reason?
        /// Habit progress for the habits hero, built once per revision and
        /// shared with `primaryReason` so habits are walked a single time.
        var habits: HabitsHeroSnapshot = .empty
        /// Facts the on-device model may rephrase `primaryReason`'s body from.
        var coachingFacts: OnDeviceSummaryEngine.Facts?
        /// Finished sessions this calendar week — the trio's first ring
        /// for a user with no active protocol.
        var workoutsThisWeek = 0
        /// The day's session count and minutes — feeds the Movement card
        /// and the checklist's training row without a fetch from `body`.
        var workoutSummary: (count: Int, minutes: Int) = (0, 0)
        /// The logging checklist. Filters the full meal and weight
        /// histories, so it's built here rather than in `body`.
        var checklist: TodayChecklistEngine.State?
        /// The shown day's supplements with their checks, under the checklist.
        var supplements: [SupplementEngine.Row] = []
    }

    private struct HeroDetailItem: Identifiable {
        let kind: HeroMetricKind
        var id: HeroMetricKind { kind }
    }

    private struct WaterLog {
        let fluidOunces: Double
        let date: Date
    }

    private enum QuickLogAction: Identifiable {
        case meal
        /// The next dose as it was when the menu row was tapped. Read
        /// live, a store change while the sheet is open could swap the
        /// sheet's entry and log the user's input against another dose.
        case dose(ProtocolEntry?)
        var id: Int {
            switch self { case .meal: 0; case .dose: 1 }
        }
    }

    private var todayStats: (entries: [ProtocolEntry], score: Double, completed: Int, total: Int) {
        let entries = dataStore.todayEntries
        let completed = entries.filter(\.completed).count
        let total = entries.count
        let score = total > 0 ? Double(completed) / Double(total) : 0
        return (entries, score, completed, total)
    }

    /// Today's dose adherence for the trio — `nil` on a day with no doses
    /// scheduled so the ring rests instead of reading 0%.
    private var adherenceRatio: Double? {
        let stats = todayStats
        return stats.total > 0 ? stats.score : nil
    }

    private var selectedDay: Date { TodayDayEngine.day(offset: dayOffset) }
    private var isViewingToday: Bool { TodayDayEngine.isToday(offset: dayOffset) }

    private func shows(_ section: TodayDayEngine.Section) -> Bool {
        TodayDayEngine.isVisible(section, isToday: isViewingToday)
    }

    /// "Yesterday" or "Mon, Oct 19" while browsing back; nil on today.
    private var pastDayTitle: String? {
        isViewingToday ? nil : MealDaySwitcher.title(for: selectedDay)
    }

    /// Today keeps the store's cached active-protocol read; a past day
    /// filters the full history for that day.
    private func doseEntries(on day: Date) -> [ProtocolEntry] {
        guard !isViewingToday else { return dataStore.todayEntries }
        return TodayDayEngine.doseEntries(
            dataStore.entries,
            on: day,
            protocolIds: Set(dataStore.protocols.map(\.id))
        )
    }

    /// Recomputes the derived Today models for the shown day. Cheap
    /// enough to run synchronously on the main actor — it's a handful of
    /// in-memory passes plus one or two workout-session fetches — but it
    /// must not run from `body`.
    private func refreshDerived() {
        let day = selectedDay
        // Today reads at the current time, so time-of-day copy (the next
        // meal) stays right; a past day reads at its start.
        let reference = isViewingToday ? Date() : day
        let plan = DailyScheduleEngine.plan(for: doseEntries(on: day))
        let habits = HabitsHeroSnapshot.build(
            activeHabits: dataStore.activeHabits,
            entries: dataStore.profile.habitEntries,
            frozenDayKeys: dataStore.profile.streakFreezeDays,
            on: day
        )
        let weekSessions = finishedWorkoutSessionsThisWeek()
        let daySessions = finishedWorkoutSessions(on: day, thisWeek: weekSessions)
        let workoutSummary = (
            count: daySessions.count,
            // Sum seconds, then round once: per-session integer minutes
            // dropped up to a minute per workout.
            minutes: (daySessions.reduce(0) { $0 + $1.elapsedSeconds() } + 30) / 60
        )
        let reason = isViewingToday ? buildPrimaryReason(plan: plan, habits: habits) : nil
        let next = DerivedToday(
            overview: TodayOverviewSnapshot.build(
                from: dataStore,
                now: reference,
                includesInsight: isViewingToday
            ),
            plan: plan,
            timeline: buildTimelineEvents(workoutSessions: daySessions, on: day),
            primaryReason: reason,
            habits: habits,
            coachingFacts: reason.flatMap { coachingFacts(for: $0) },
            workoutsThisWeek: weekSessions.count,
            workoutSummary: workoutSummary,
            checklist: TodayChecklistEngine.state(
                profile: dataStore.profile,
                consumption: dataStore.consumption(for: day),
                trainedToday: workoutSummary.count > 0,
                steps: steps(on: day),
                now: reference
            ),
            supplements: SupplementEngine.rows(dataStore.profile.supplements, on: reference, calendar: .current)
        )
        // Inside an animation so the cards' numericText digits roll.
        AppAnimation.with(AppAnimation.springSmooth) { derived = next }
        refreshWeeklyCheckIn()
    }

    private func refreshWeeklyCheckIn() {
        let next = dataStore.weeklyCheckIn(sleepHours: checkInSleep)
        AppAnimation.with(AppAnimation.springSmooth) { weeklyCheckIn = next }
    }

    /// Sleep nights for the check-in. Health-backed, so it moves without a
    /// store mutation and refreshes with the other HealthKit reads.
    private func refreshCheckInSleep() async {
        checkInSleep = dataStore.profile.healthConnected
            ? await HealthKitService.shared.dailySleepHours(days: 14)
            : []
        refreshWeeklyCheckIn()
    }

    /// Rebuilds everything that depends on the clock rather than the store —
    /// the derived models (day rollover, the time-of-day next meal and
    /// coaching copy) and the HealthKit-backed rings, which can move without
    /// any store mutation: overnight sleep, a new HRV sample.
    private func refreshForCurrentTime() {
        refreshDerived()
        Task { await refreshHeroSnapshot() }
        Task { await refreshHealthRange() }
        Task { await refreshSteps() }
        Task { await refreshCheckInSleep() }
    }

    /// Nil without a Health connection, or when Health has no step data
    /// for the day — the checklist then drops its steps row.
    private func steps(on day: Date) -> Double? {
        guard dataStore.profile.healthConnected else { return nil }
        return StepGoalEngine.steps(on: day, from: stepBuckets)
    }

    /// Fetches the step window for the shown day and folds the count
    /// into the checklist without rebuilding the rest of Today.
    private func refreshSteps() async {
        if dataStore.profile.healthConnected {
            stepBuckets = await HealthKitService.shared.dailySteps(days: StepGoalEngine.fetchDays(forDayOffset: dayOffset))
        } else {
            stepBuckets = []
        }
        let count = steps(on: selectedDay)
        guard derived.checklist?.steps != count else { return }
        AppAnimation.with(AppAnimation.springSmooth) { derived.checklist?.steps = count }
    }

    /// The week's finished sessions — one fetch that also covers today, so
    /// the weekly count, Movement summary and timeline share it.
    private func finishedWorkoutSessionsThisWeek() -> [WorkoutSession] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return SwiftDataRepository.shared
            .loadWorkoutSessions(startedBetween: week.start..<week.end)
            .filter { !$0.isActive }
    }

    /// The shown day's finished sessions. A day in the current week reuses
    /// the week fetch; an earlier day reads its own midnight-to-midnight
    /// window.
    private func finishedWorkoutSessions(on day: Date, thisWeek weekSessions: [WorkoutSession]) -> [WorkoutSession] {
        let calendar = Calendar.current
        if let week = calendar.dateInterval(of: .weekOfYear, for: Date()), week.contains(day) {
            return weekSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        }
        return SwiftDataRepository.shared
            .loadWorkoutSessions(startedBetween: TodayDayEngine.dayRange(for: day))
            .filter { !$0.isActive }
    }

    /// Touches `notificationService.lastReport` so the View takes a SwiftUI
    /// observation dependency on it — without this, the dependency is on
    /// DataStore.notificationReport which reads a non-observed singleton
    /// and so the banner won't refresh after a reschedule.
    private var shouldShowNotificationBanner: Bool {
        notificationService.lastReport.hasAnyIssue && !notificationBannerDismissed
    }

    /// Gates both the doses section and its jump chip, so the chip never
    /// scrolls to a section that isn't rendered.
    private var showsDoseSection: Bool {
        !dataStore.protocols.isEmpty && derived.plan != nil
    }

    /// The "At a glance" trio only has meaning once there's a data
    /// source — an active protocol, a Health connection, or a workout
    /// logged this week. Hidden otherwise so a day-0 user isn't met with
    /// zero rings that read as failure.
    private var showsAtAGlance: Bool {
        !dataStore.activeProtocols.isEmpty
            || dataStore.profile.healthConnected
            || derived.workoutsThisWeek > 0
    }

    /// Adherence leads for protocol users; everyone else sees this
    /// week's training against their days-per-week target, so Today
    /// doesn't open on a dose metric they never asked for.
    private var heroLeading: HeroLeadingMetric {
        guard dataStore.activeProtocols.isEmpty else { return .adherence }
        return .workouts(
            done: derived.workoutsThisWeek,
            target: max(1, dataStore.profile.trainingPreferences?.daysPerWeek ?? TrainingPreferences().daysPerWeek)
        )
    }

    var body: some View {
        let stats = todayStats

        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    WelcomeHeader(
                        greeting: greeting,
                        name: dataStore.profile.name,
                        date: dateString,
                        avatarImageData: dataStore.profile.avatarImageData,
                        onAvatarTap: {
                            Haptics.impact(.light)
                            // Profile lost its tab slot in the training
                            // pivot; the shared flag opens the app-level
                            // sheet from here and every other tab alike.
                            appState.showProfile = true
                        }
                    )
                    .sectionAppear(index: 0)
                    .scrollHandOff()

                    // Browse back through earlier days — the Meals tab's
                    // switcher, so both screens pick days the same way.
                    VStack(spacing: Spacing.sm) {
                        MealDaySwitcher(offset: $dayOffset)
                        if let pastDayTitle {
                            PastDayBanner(dayTitle: pastDayTitle, onBackToToday: backToToday)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .sectionAppear(index: 1)

                    // Today reads status → recommendation → action
                    // (Product Architecture 07). The removed
                    // TodayContextRow duplicated the date shown one
                    // line above and hid the Library behind an
                    // unlabeled pill; the Protocols section header
                    // below carries a labeled Manage entry instead.
                    // ProtocolScoreCard is gone too — its score was
                    // the trio's adherence ring restated, and its
                    // streak/weekly strip is analysis, which lives in
                    // the adherence detail sheet.

                    // Quick-jump chips — scroll shortcuts to the
                    // sections below plus the "+ Log" quick-log
                    // button, reachable above the fold. Tab
                    // destinations were dropped from the chip row;
                    // the tab bar already does that job.
                    if shows(.quickActions) {
                        TodayJumpBar(
                            activeAnchor: activeJumpAnchor,
                            showsDoses: showsDoseSection,
                            hiddenAnchors: hiddenJumpAnchors,
                            onSelect: { anchor in handleJump(to: anchor, proxy: proxy) },
                            isQuickLogOpen: showQuickLogSheet,
                            quickLogIncludesDose: dataStore.nextDose != nil,
                            onQuickLog: {
                                // A one-row menu is just an extra tap.
                                if dataStore.nextDose == nil {
                                    quickLogAction = .meal
                                } else {
                                    showQuickLogSheet = true
                                }
                            }
                        )
                        .sectionAppear(index: 1)
                    }

                    // Observed via the @State notificationService so the banner
                    // re-renders when a reschedule writes a fresh report. Reading
                    // through DataStore's passthrough wouldn't trigger redraw.
                    if shows(.notificationBanner),
                       shouldShowNotificationBanner,
                       let report = dataStore.notificationReport {
                        NotificationIssueBanner(
                            report: report,
                            droppedProtocolNames: dataStore.droppedReminderProtocolNames,
                            onReview: {
                                appState.pendingProtocolList = true
                                appState.showLibrary = true
                            },
                            onDismiss: {
                                AppAnimation.with(AppAnimation.toast) { notificationBannerDismissed = true }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .sectionAppear(index: 1)
                    }

                    // The user's arrangement of Today. The default order
                    // reads status → recommendation → action → analysis
                    // (Product Architecture 07).
                    ForEach(dataStore.profile.todayLayout.visibleSections) { section in
                        todaySection(section, proxy: proxy)
                    }

                    customizeTodayButton
                }
                .appAnimation(AppAnimation.toast, value: shouldShowNotificationBanner)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                .readableContentWidth()
            }
            // Scroll-driven sticky header progress: fade begins
            // once the welcome card scrolls ~80pt out of view and
            // completes after another ~60pt — about a single finger
            // pan. Clamped 0…1 so the math behaves at the extremes.
            .onScrollGeometryChange(for: Double.self) { proxy in
                let raw = max(0, proxy.contentOffset.y - 80)
                return min(raw / 60, 1.0)
            } action: { _, newValue in
                stickyProgress = newValue
            }
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { pendingJumpAnchor = nil }
            }
            // Scroll-tracked jump-bar active anchor. Each tagged
            // section publishes its frame via SectionAnchorFrameKey;
            // ActiveSectionPicker reduces the dictionary to the
            // anchor whose top edge is closest to (but not past)
            // the header inset. Only writes when the picked anchor
            // actually changes — keeps the chip-bar from re-
            // rendering on every scroll tick.
            .coordinateSpace(name: "HomeScroll")
            .onPreferenceChange(SectionAnchorFrameKey.self) { frames in
                guard pendingJumpAnchor == nil else { return }
                let picked = ActiveSectionPicker.pick(from: frames)
                if picked != activeJumpAnchor {
                    activeJumpAnchor = picked
                }
            }
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeStickyHeader(
                    firstName: firstNameForSticky,
                    avatarImageData: dataStore.profile.avatarImageData,
                    onAvatarTap: {
                        Haptics.impact(.light)
                        appState.showProfile = true
                    },
                    progress: $stickyProgress
                )
            }
            .sheet(item: $selectedEntry) { entry in
                DoseLoggingSheet(
                    entry: entry,
                    lastInjectionSite: entry.lastInjectionSite(in: dataStore.entries)
                ) { actualDose, actualTime, site, notes in
                    dataStore.logDose(
                        entryId: entry.id,
                        actualDose: actualDose,
                        actualTime: actualTime,
                        injectionSite: site,
                        notes: notes
                    )
                }
                .liquidGlassPresentation()
            }
            .sheet(isPresented: $showProgress) {
                AtlasProgressView()
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showResearchAssistant) {
                AIResearchView()
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            // One save per editing session rather than one per drag.
            .sheet(isPresented: $showEditToday, onDismiss: { dataStore.persistProfile() }) {
                EditTodaySheet(layout: todayLayoutBinding)
                    .liquidGlassPresentation()
            }
            // Stack-warning / stack-adjustment / paywall sheets
            // moved to ProtocolsStackHealthSection in Phase 34 —
            // their host cards live on the Protocols tab now, so
            // chaining the sheets there avoids a cross-tab modal
            // dance.
            .sheet(isPresented: $showTargetsEditor) {
                NutritionTargetsEditor(
                    initial: dataStore.profile.nutritionTargets ?? .zero,
                    bodyMetrics: dataStore.profile.bodyMetrics,
                    goalRaw: dataStore.profile.primaryGoal,
                    expenditure: dataStore.expenditureEstimate(),
                    onSave: { targets in
                        dataStore.updateNutritionTargets(targets)
                        showTargetsEditor = false
                    },
                    onCancel: { showTargetsEditor = false }
                )
                .liquidGlassPresentation()
            }
            .sheet(item: $milestonePrompt) { item in
                CycleMilestonePromptSheet(
                    proto: item.proto,
                    milestone: item.milestone,
                    onShare: {
                        let proto = item.proto
                        milestonePrompt = nil
                        // Defer one runloop tick so the prompt sheet has
                        // finished dismissing before the share sheet mounts —
                        // SwiftUI can't chain two sheets in the same tick.
                        Task { @MainActor in
                            try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                            milestoneShareProtocol = proto
                        }
                    },
                    onDismiss: { milestonePrompt = nil }
                )
                .liquidGlassPresentation(detents: [.medium])
                // Every exit — share, dismiss or swipe-down — marks the
                // milestone shown so it doesn't re-fire on the next appear.
                .onDisappear {
                    CycleMilestoneService.shared.markShown(item.milestone, for: item.proto)
                }
            }
            .sheet(item: $completionPrompt) { item in
                CycleCompletionPromptSheet(
                    proto: item.proto,
                    daysPastEnd: item.daysPastEnd,
                    onMarkComplete: {
                        dataStore.updateProtocolStatus(id: item.proto.id, to: .completed)
                        CycleCompletionService.shared.markAutoCompleted(item.proto)
                        completionPromptResolved = true
                        completionPrompt = nil
                    },
                    onExtend: {
                        // Extending the cycle pushes `endDate` out,
                        // so `pendingCompletion` naturally stops
                        // returning this protocol until the new
                        // window expires — no suppression marker
                        // needed. Calling `markAutoCompleted` here
                        // (the previous behaviour) shared a key with
                        // the now-extended cycle (same id + same
                        // startDate) and permanently silenced the
                        // prompt for every future end-of-cycle on
                        // this protocol. Clear the dismiss counter
                        // instead so subsequent dismissals on the
                        // extended cycle start from zero.
                        CycleCompletionService.shared.resetDismissals(for: item.proto)
                        dataStore.extendProtocol(id: item.proto.id, byWeeks: 2)
                        completionPromptResolved = true
                        completionPrompt = nil
                    },
                    onStartNewCycle: {
                        // Mark BEFORE restarting so the suppression key
                        // is recorded against the pre-restart startDate
                        // (the cycle that actually ended).
                        CycleCompletionService.shared.markAutoCompleted(item.proto)
                        dataStore.restartProtocol(id: item.proto.id)
                        completionPromptResolved = true
                        completionPrompt = nil
                    },
                    onDismiss: { completionPrompt = nil }
                )
                .liquidGlassPresentation(detents: [.medium, .large])
                .onDisappear {
                    if !completionPromptResolved {
                        CycleCompletionService.shared.recordDismissal(for: item.proto)
                    }
                    completionPromptResolved = false
                }
            }
            .sheet(item: $milestoneShareProtocol) { proto in
                ShareCardSheet(subject: .singleProtocol(proto))
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .overlay(alignment: .top) {
                // Bevel-style sync-complete pill. The toast manages
                // its own auto-dismiss timer (2.4s) so we just bind
                // the visibility flag and forget about it.
                VStack(spacing: Spacing.xs) {
                    SyncToast(isShowing: $showSyncToast)
                    SyncToast(
                        isShowing: $showWaterToast,
                        message: waterToastMessage,
                        autoDismissAfter: AppAnimation.logSuccessAutoCloseDelay,
                        action: .init(label: "Undo", perform: undoWaterGlass),
                        presentationID: waterToastID
                    )
                }
                .padding(.top, Spacing.sm)
            }
            // Single handler for adherence-ratio changes: update only the
            // trio's Adherence ring so a logged/unlogged dose shows
            // immediately without re-reading HealthKit, and fire the
            // review prompt when the day first hits 100%. Keyed on the
            // optional ratio so going from no doses to N untaken (nil → 0)
            // still reaches the ring.
            .onChange(of: adherenceRatio) { oldRatio, newRatio in
                AppAnimation.with(AppAnimation.springSmooth) {
                    heroSnapshot = heroSnapshot.withAdherence(newRatio)
                }
                if (oldRatio ?? 0) < 1.0, (newRatio ?? 0) >= 1.0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
                    }
                }
            }
            // Recompute the derived Today models once per store mutation.
            // `.task(id:)` cancels and re-runs on each new revision, and fires
            // once on first appear, which covers the initial population too.
            .task(id: DerivedKey(revision: dataStore.revision, dayOffset: dayOffset)) {
                refreshDerived()
            }
            // Refetch steps for a newly browsed day and once Health connects.
            // Today's count keeps moving while the screen stays open, so it
            // is re-read every few minutes; past days are final.
            .task(id: StepsKey(dayOffset: dayOffset, healthConnected: dataStore.profile.healthConnected)) {
                await refreshSteps()
                while dayOffset == 0, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(StepGoalEngine.liveRefreshSeconds))
                    guard !Task.isCancelled, scenePhase == .active else { continue }
                    await refreshSteps()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshForCurrentTime() }
            }
            // Neither notification promises main-thread delivery.
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                refreshForCurrentTime()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                refreshForCurrentTime()
            }
            // The coaching copy reads recovery + sleep off the hero snapshot,
            // so it has to re-pick when that lands (it arrives async, after
            // the first `refreshDerived()`).
            .onChange(of: heroSnapshot) { _, _ in
                // A past day's plan isn't today's, and its coaching is hidden.
                guard isViewingToday else { return }
                let plan = derived.plan ?? DailyScheduleEngine.plan(for: dataStore.todayEntries)
                let reason = buildPrimaryReason(plan: plan, habits: derived.habits)
                let facts = coachingFacts(for: reason)
                AppAnimation.with(AppAnimation.springSmooth) {
                    derived.primaryReason = reason
                    derived.coachingFacts = facts
                }
            }
            .onAppear {
                checkMilestonePrompt()
                consumePendingDoseDeepLink()
                consumeWeeklyDeepLink()
                Task { await loadWeeklySummary(forceRefresh: false) }
                Task { await refreshHeroSnapshot() }
                Task { await refreshHealthRange() }
                Task { await refreshCheckInSleep() }
            }
            .onChange(of: notificationService.lastReport.droppedProtocolIDs) { _, _ in
                notificationBannerDismissed = false
            }
            .onChange(of: appState.pendingDoseLogEntryId) { _, _ in
                consumePendingDoseDeepLink()
            }
            .onChange(of: appState.pendingWeeklyRecap) { _, _ in
                consumeWeeklyDeepLink()
            }
            .navigationDestination(item: $detailWeekStart) { weekStart in
                if let binding = bindingForWeeklySummary(weekStart: weekStart) {
                    // Refresh only regenerates the current week, so an
                    // older recap opened by deep link gets no button
                    // rather than one that overwrites a different week.
                    WeeklySummaryDetailView(
                        summary: binding,
                        onRefresh: isCurrentWeek(weekStart)
                            ? { await loadWeeklySummary(forceRefresh: true) }
                            : nil,
                        // The check-in is about the last seven days, so it
                        // belongs only on this week's recap.
                        checkIn: isCurrentWeek(weekStart) ? weeklyCheckIn : nil,
                        unit: dataStore.profile.bodyMetrics.unit
                    )
                } else {
                    // The summary was deleted between push and render —
                    // show a real empty state instead of a blank
                    // pushed screen with only a back button.
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: "Recap unavailable",
                        message: "This weekly recap is no longer available."
                    )
                }
            }
            .sheet(item: $quickLogAction, content: quickLogSheet)
            .sheet(item: $heroDetailKind) { item in
                HeroMetricDetailSheet(
                    kind: item.kind,
                    snapshot: heroSnapshot,
                    context: .init(
                        todayEntries: stats.entries,
                        recoveryComponents: heroSnapshot.recoveryComponents,
                        lastSleepHours: heroSnapshot.lastSleepHours
                    ),
                    onLogDose: { entry in selectedEntry = entry }
                )
                .environment(dataStore)
                .environment(appState)
                .liquidGlassPresentation()
            }
            .sheet(isPresented: $showWeightSheet) {
                LogWeightSheet()
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showSupplements) {
                SupplementsSheet()
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showQuickLogSheet) {
                QuickLogMenuSheet(
                    nextDose: dataStore.nextDose,
                    onSnapMeal: { startQuickLog(.meal) },
                    onLogNextDose: { startQuickLog(.dose(dataStore.nextDose)) }
                )
            }
            }   // closes ScrollViewReader
        }
    }

    // MARK: - Sections

    /// Jump chips whose section the user hid — nothing for them to scroll to.
    private var hiddenJumpAnchors: Set<TodayJumpBar.SectionAnchor> {
        let shown = Set(dataStore.profile.todayLayout.visibleSections)
        return Set(TodayJumpBar.SectionAnchor.allCases.filter { !shown.contains($0.todaySection) })
    }

    private var todayLayoutBinding: Binding<TodayLayout> {
        Binding(
            get: { dataStore.profile.todayLayout },
            set: { dataStore.profile.todayLayout = $0 }
        )
    }

    /// A section renders when the browsed day has something for it —
    /// live, today-only sections drop out on a past day.
    @ViewBuilder
    private func todaySection(_ section: TodaySection, proxy: ScrollViewProxy) -> some View {
        if shows(section.dayEngineSection) {
            todaySectionContent(section, proxy: proxy)
        }
    }

    @ViewBuilder
    private func todaySectionContent(_ section: TodaySection, proxy: ScrollViewProxy) -> some View {
        switch section {
        case .atAGlance: atAGlanceSection
        case .coaching: coachingSection(proxy: proxy)
        case .weeklyRecap: weeklyRecapSection
        case .habits: habitsSection
        case .checklist: checklistSection
        case .doses: dosesSection
        case .wellness: wellnessSection
        case .movement: movementSection
        case .steps: stepsSection
        case .overview: overviewSection(proxy: proxy)
        case .momentum: momentumSection
        case .explore: exploreSection
        case .timeline: timelineSection(proxy: proxy)
        case .healthMonitor: healthMonitorSection
        }
    }

    /// PRIMARY STATUS. Hide the adherence/recovery/sleep trio for a
    /// brand-new user with no protocols and no Health connection — all
    /// zeros read as failure (roadmap day-0). They lead with the habit
    /// hero; the trio's footer offers Connect Health.
    @ViewBuilder
    private var atAGlanceSection: some View {
        if showsAtAGlance {
            VStack(spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Today", title: "At a glance")

                // Bevel-style hero trio — Adherence / Recovery /
                // Sleep. Three at-a-glance numbers mapping to the
                // user's mental model from Whoop / Oura / Bevel.
                HeroMetricTrio(
                    snapshot: heroSnapshot,
                    onTapRing: { kind in
                        Haptics.impact(.light)
                        heroDetailKind = HeroDetailItem(kind: kind)
                    },
                    onConnectHealth: connectHealth,
                    leading: heroLeading,
                    onTapWorkouts: {
                        Haptics.impact(.light)
                        appState.selectedTab = .train
                    },
                    isLoading: isHeroLoading
                )
            }
            .sectionAppear(index: 2)
        }
    }

    /// PRIMARY RECOMMENDATION — the one thing `PrimaryReasonEngine`
    /// ranked highest across recovery/sleep coaching, today's dose plan,
    /// habits due, and a freshly-changed weekly review. Same single-card
    /// discipline Bevel uses ("Excellent recovery, push today" / "Short
    /// sleep, cap intensity") — just reconciled across more signals
    /// than coaching alone used to see.
    @ViewBuilder
    private func coachingSection(proxy: ScrollViewProxy) -> some View {
        if let reason = derived.primaryReason {
            // Keyed on the title so a new recommendation
            // cross-fades in rather than swapping text in place.
            CoachingCard(
                message: reason.message,
                rephrasedBody: derived.coachingFacts.flatMap { summaryService.text(for: $0) },
                onAction: isViewingToday ? { handleCoachingAction($0, proxy: proxy) } : nil
            )
                .id(reason.message.title)
                .transition(.opacity.combined(with: .scale(0.98)))
                .sectionAppear(index: 3)
                .task(id: derived.coachingFacts) {
                    if let facts = derived.coachingFacts { await summaryService.prepare(facts) }
                }
        }
    }

    @ViewBuilder
    private var weeklyRecapSection: some View {
        if let weeklyState = weeklySummaryState,
           WeeklySummaryService.shared.isAvailable(profile: dataStore.profile),
           shouldShowWeeklyRecapOnToday {
            WeeklySummaryHeroCard(
                state: weeklyState,
                onTap: {
                    if case .ready(let summary) = weeklyState {
                        detailWeekStart = summary.weekStart
                    }
                },
                onRetry: { Task { await loadWeeklySummary(forceRefresh: true) } }
            )
            .sectionAppear(index: 3)
        }
        if let weeklyCheckIn, WeeklyCheckInEngine.isCheckInDay(Date(), calendar: .current) {
            WeeklyCheckInCard(
                checkIn: weeklyCheckIn,
                unit: dataStore.profile.bodyMetrics.unit,
                onLogWeight: { showWeightSheet = true }
            )
            .transition(.opacity.combined(with: .scale(0.98)))
            .sectionAppear(index: 3)
        }
    }

    /// PRIMARY ACTION — today's habits, the daily completion ring, and
    /// the active streak. Per-habit summary work is snapshotted off-body
    /// inside the component (audit A6).
    /// A past day drops the empty-state CTA — there's nothing to record
    /// for a day before any habit.
    @ViewBuilder
    private var habitsSection: some View {
        if isViewingToday || !dataStore.activeHabits.isEmpty {
            TodayHabitsHero(snapshot: derived.habits, day: isViewingToday ? nil : selectedDay)
                .sectionAppear(index: 4)
                .id(TodaySection.habits)
        }
    }

    /// The day's logging loop in one card — every open row is also the
    /// shortcut that closes it. A past day gets the record without the
    /// shortcuts.
    @ViewBuilder
    private var checklistSection: some View {
        if let checklist = derived.checklist {
            TodayChecklistCard(
                state: checklist,
                unit: dataStore.profile.bodyMetrics.unit,
                onAction: checklistAction,
                dayTitle: pastDayTitle,
                supplements: derived.supplements,
                onToggleSupplement: supplementToggle,
                onManageSupplements: supplementManager
            )
            .sectionAppear(index: 5)
        }
    }

    /// The ONE place doses appear on Today — the overview card and the
    /// timeline leave them out. The header's Manage button is the
    /// labeled Library entry that replaced the removed cycle pill.
    @ViewBuilder
    private var dosesSection: some View {
        if showsDoseSection, let plan = derived.plan, isViewingToday || plan.hasAny {
            VStack(spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Protocols", title: isViewingToday ? "Today's doses" : "Doses") {
                    Button {
                        Haptics.impact(.light)
                        appState.pendingProtocolList = true
                        appState.showLibrary = true
                    } label: {
                        Text("Manage")
                            .font(AppFont.chipText)
                            .foregroundStyle(AppColor.accentLight)
                    }
                    .minimumHitArea()
                    .accessibilityLabel("Manage protocols")
                }

                if isViewingToday {
                    DailyPlanCard(
                        plan: plan,
                        hasActiveProtocols: !dataStore.activeProtocols.isEmpty,
                        onTapDose: { entry in selectedEntry = entry },
                        onToggleDose: toggleDose,
                        onAddProtocol: {
                            appState.pendingProtocolList = true
                            appState.showLibrary = true
                        }
                    )
                } else {
                    // Taken/pending as recorded; no toggles.
                    DailyPlanCard(plan: plan, hasActiveProtocols: !dataStore.activeProtocols.isEmpty)
                }
            }
            .id(TodayJumpBar.SectionAnchor.doses)
            .trackSectionAnchor(.doses)
            .scrollReveal()
        }
    }

    private var wellnessSection: some View {
        HomeWellnessSection()
            .id(TodayJumpBar.SectionAnchor.wellness)
            .trackSectionAnchor(.wellness)
            .scrollReveal()
    }

    private var movementSection: some View {
        HomeMovementSection(summary: derived.workoutSummary, isPastDay: !isViewingToday)
            .id(TodayJumpBar.SectionAnchor.movement)
            .trackSectionAnchor(.movement)
            .scrollReveal()
    }

    /// The shown day's steps against the goal. Hidden without Health
    /// step data, like the checklist's steps row.
    @ViewBuilder
    private var stepsSection: some View {
        if let checklist = derived.checklist, let steps = checklist.steps {
            TodayStepsCard(steps: steps, goal: checklist.stepGoal, isPastDay: !isViewingToday)
                .scrollReveal()
        }
    }

    /// Lifestyle overview: calorie / streak / check-in / water grid and
    /// the rotating insight.
    @ViewBuilder
    private func overviewSection(proxy: ScrollViewProxy) -> some View {
        if let overview = derived.overview, overview.hasAnySignal {
            // Headed like every other Today section, so the grid reads as
            // its own group rather than a stray card.
            VStack(spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Lifestyle", title: "Overview")
                overviewCard(overview, proxy: proxy)
            }
            .scrollReveal()
        }
    }

    private func overviewCard(_ overview: TodayOverviewSnapshot, proxy: ScrollViewProxy) -> some View {
        TodayOverviewCard(
            snapshot: overview,
            unit: dataStore.profile.bodyMetrics.unit,
            onTapInsight: { insight in
                switch insight {
                case .latestLab:
                    appState.pendingLabsOpen = true
                    appState.selectedTab = .biology
                case .nudge(_, _, _, .setCalorieTarget):
                    showTargetsEditor = true
                case .nudge(_, _, _, .logMeal):
                    appState.selectedTab = .meals
                case .protocolInsight:
                    break
                }
            },
            // Tiles log and route for today; a past day's tiles are a
            // read-only record.
            onTapTile: isViewingToday
                ? { tile in handleOverviewTile(tile, proxy: proxy) }
                : nil,
            isToday: isViewingToday
        )
    }

    /// Momentum — goal countdown for users who committed to a target
    /// date, and the earned Atlas Score (level / tier / progress). The
    /// goal half is guarded so its header never sits alone when no goal
    /// date is set.
    @ViewBuilder
    private var momentumSection: some View {
        if GoalCountdownCard.isShown(goalDate: dataStore.profile.goalDate) {
            VStack(spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Momentum", title: "Your goal")

                GoalCountdownCard(
                    goalDate: dataStore.profile.goalDate,
                    primaryGoal: dataStore.profile.primaryGoal,
                    startDate: dataStore.profile.memberSince
                )
            }
            .scrollReveal()
        }

        AtlasScoreCard(onTap: { showProgress = true })
            .scrollReveal()
    }

    /// The AI research chat's only other entry is an icon in the Library
    /// toolbar. Pro opens the chat; free users see the paywall for it
    /// from the root. Protocol tracking is an optional advanced feature,
    /// so with zero protocols its entry sits here with the other explore
    /// rows — still one labeled row, so the Library stays findable.
    @ViewBuilder
    private var exploreSection: some View {
        ResearchAssistantRow(isLocked: !StoreService.shared.isProUser) {
            if StoreService.shared.isProUser {
                showResearchAssistant = true
            } else {
                appState.presentedPaywall = .aiResearch
            }
        }
        .scrollReveal()

        if dataStore.protocols.isEmpty {
            ProtocolsDiscoverRow {
                appState.pendingProtocolList = true
                appState.showLibrary = true
            }
            .scrollReveal()
        }
    }

    /// Bevel-style chronological feed — meals, check-in and workouts
    /// merged into one sorted list (doses stay in their own section).
    /// Hides itself when the day has no events (a brand-new install
    /// before the first log).
    private func timelineSection(proxy: ScrollViewProxy) -> some View {
        TodayTimelineCard(
            events: derived.timeline,
            // A past day's rows stay display-only: Meals and Train open on
            // today, not the day being read.
            onTap: isViewingToday
                ? { event in handleTimelineTap(event, proxy: proxy) }
                : nil
        )
        .scrollReveal()
    }

    /// Bevel-style Health Monitor grid — HRV / RHR / Sleep with
    /// personal-range indicators. Hides individual cards (or the whole
    /// grid) when there's not enough HealthKit history to render a
    /// meaningful range.
    private var healthMonitorSection: some View {
        HealthMonitorGrid(snapshot: healthRange)
            .scrollReveal()
    }

    /// Opens "Edit Today". Sits at the end of the scroll — the place a
    /// user who wants a different Today has just reached.
    private var customizeTodayButton: some View {
        Button {
            Haptics.impact(.light)
            showEditToday = true
        } label: {
            Label("Customize Today", systemImage: "slider.horizontal.3")
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassControl(.capsule, interactive: false)
        }
        .buttonStyle(ScalePressStyle())
    }

    // MARK: - Quick-log routing

    /// Routes a jump-bar chip tap to a scroll target or a tab switch.
    /// `.biology` jumps to the Biology tab via `AppState`; every
    /// other anchor scrolls within Today's existing `ScrollViewReader`.
    private func handleJump(to anchor: TodayJumpBar.SectionAnchor, proxy: ScrollViewProxy) {
        // Every chip scrolls within Today now — the Meals and Biology
        // chips that duplicated the tab bar were dropped (Product
        // Architecture 07: no duplicate destinations).
        AppAnimation.with(AppAnimation.settle) {
            proxy.scrollTo(anchor, anchor: .top)
        }
        pendingJumpAnchor = anchor
        activeJumpAnchor = anchor
    }

    private func handleCoachingAction(_ action: CoachingMessageEngine.CoachingMessage.Action, proxy: ScrollViewProxy) {
        switch action {
        case .connectHealth:
            connectHealth()
        case .scrollToHabits:
            Haptics.impact(.light)
            AppAnimation.with(AppAnimation.settle) {
                proxy.scrollTo(TodaySection.habits, anchor: .top)
            }
        case .scrollToDoses:
            Haptics.impact(.light)
            handleJump(to: .doses, proxy: proxy)
        }
    }

    private func backToToday() {
        AppAnimation.with(AppAnimation.springSnappy) { dayOffset = 0 }
    }

    /// Nil on a past day, which makes the checklist read-only.
    private var checklistAction: ((TodayChecklistEngine.Item) -> Void)? {
        guard isViewingToday else { return nil }
        return handleChecklistAction
    }

    /// Asks HealthKit directly from the trio's footer rather than
    /// sending the user to hunt for the Health row in Profile.
    private func connectHealth() {
        Haptics.impact(.light)
        Task { @MainActor in
            guard !dataStore.profile.healthConnected,
                  await dataStore.toggleHealthConnection() else { return }
            await refreshHeroSnapshot()
            await refreshHealthRange()
        }
    }

    private func handleOverviewTile(_ tile: TodayOverviewCard.Tile, proxy: ScrollViewProxy) {
        Haptics.impact(.light)
        switch tile {
        case .calories:
            if dataStore.profile.nutritionTargets == nil {
                showTargetsEditor = true
            } else {
                appState.selectedTab = .meals
            }
        case .mealStreak:
            appState.selectedTab = .meals
        case .checkIn:
            handleJump(to: .wellness, proxy: proxy)
        case .water:
            logWaterGlass()
        }
    }

    private func handleTimelineTap(_ event: TodayTimelineEvent, proxy: ScrollViewProxy) {
        Haptics.impact(.light)
        switch event.tint {
        case .meal:
            appState.selectedTab = .meals
        case .workout:
            appState.selectedTab = .train
        case .checkIn:
            handleJump(to: .wellness, proxy: proxy)
        }
    }

    /// The dose row's one-tap check. A success haptic marks the dose
    /// taken; un-checking gets a soft tap.
    private func toggleDose(_ entry: ProtocolEntry) {
        if entry.completed { Haptics.impact(.soft) } else { Haptics.success() }
        AppAnimation.with(AppAnimation.springSnappy) { dataStore.toggleEntry(entry.id) }
    }

    /// Nil on a past day: its supplement checks are a record, not a control.
    private var supplementToggle: ((UUID) -> Void)? {
        guard isViewingToday else { return nil }
        return toggleSupplement
    }

    private var supplementManager: (() -> Void)? {
        guard isViewingToday else { return nil }
        return { showSupplements = true }
    }

    /// The supplement row's one-tap check, with the same feedback as a
    /// dose: a success haptic when taken, a soft tap when un-checked.
    private func toggleSupplement(_ id: UUID) {
        let wasTaken = derived.supplements.first(where: { $0.id == id })?.isTaken ?? false
        if wasTaken { Haptics.impact(.soft) } else { Haptics.success() }
        AppAnimation.with(AppAnimation.springSnappy) { dataStore.toggleSupplement(id: id) }
    }

    private func handleChecklistAction(_ item: TodayChecklistEngine.Item) {
        switch item {
        case .meals:
            quickLogAction = .meal
        case .training:
            appState.selectedTab = .train
        case .water:
            logWaterGlass()
        case .weight:
            showWeightSheet = true
        case .steps:
            // Display-only: steps fill from Health.
            break
        }
    }

    /// One glass from the checklist row or the overview tile. Both are
    /// a single tap that a scroll can trigger by mistake, so each log
    /// opens an Undo toast.
    private func logWaterGlass() {
        let glass = TodayChecklistEngine.glassFluidOunces(for: dataStore.profile.bodyMetrics.unit)
        let date = Date()
        dataStore.logWater(fluidOunces: glass, date: date)
        lastWaterLog = WaterLog(fluidOunces: glass, date: date)
        waterToastMessage = LocalizedStringResource(
            "Added \(dataStore.profile.bodyMetrics.unit.volumeLabel(glass))",
            comment: "Toast after a one-tap water log on Today. The value is the amount with its unit."
        )
        waterToastID += 1
        showWaterToast = true
    }

    private func undoWaterGlass() {
        guard let log = lastWaterLog else { return }
        dataStore.logWater(fluidOunces: -log.fluidOunces, date: log.date)
        Haptics.impact(.light)
        lastWaterLog = nil
    }

    /// Closes the quick-log menu, then mounts the picked flow once the
    /// menu has finished dismissing — SwiftUI drops a second sheet that
    /// races the first on the same tick.
    private func startQuickLog(_ action: QuickLogAction) {
        showQuickLogSheet = false
        Task { @MainActor in
            try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
            quickLogAction = action
        }
    }

    /// The shown day's chronological event feed for `TodayTimelineCard`.
    /// Pulls meals + check-in + the day's finished workouts and hands them
    /// to the pure `TodayTimelineEvent.build` for sorting + row
    /// construction.
    private func buildTimelineEvents(workoutSessions: [WorkoutSession], on day: Date) -> [TodayTimelineEvent] {
        // Plan C: workouts now live in StoredWorkoutSession; the
        // timeline still expects the legacy `WorkoutEntry` shape, so
        // adapt at this boundary. Empty-exercise quick-log sessions
        // still render — the timeline only needs name + date +
        // duration.
        let workoutsOnDay: [WorkoutEntry] = workoutSessions
            .map { session in
                let sets = session.exercises.flatMap(\.sets)
                let reps = sets.reduce(0) { $0 + $1.reps }
                let avgReps = sets.isEmpty ? 0 : reps / sets.count
                return WorkoutEntry(
                    id: session.id,
                    date: session.startedAt,
                    name: session.displayName,
                    sets: sets.count,
                    reps: avgReps,
                    durationMinutes: (session.elapsedSeconds() + 30) / 60
                )
            }
        return TodayTimelineEvent.build(
            meals: dataStore.mealEntries(for: day),
            checkIn: dataStore.outcome(for: day),
            workouts: workoutsOnDay
        )
    }

    /// Builds the coaching context from the current store + hero
    /// snapshot. Pure read — synchronous so the view body can
    /// consume it without an async hop.
    private func buildCoachingContext() -> CoachingMessageEngine.Context {
        let stats = todayStats
        let next = dataStore.nextDose
        let nextTimeDisplay: String? = next.map {
            DateFormatter.localizedString(from: $0.date, dateStyle: .none, timeStyle: .short)
        }
        let memberDays = Calendar.current
            .dateComponents([.day], from: dataStore.profile.memberSince, to: Date())
            .day ?? 0
        return CoachingMessageEngine.Context(
            hasProtocols: !dataStore.protocols.isEmpty,
            healthConnected: dataStore.profile.healthConnected,
            recoveryScore: heroSnapshot.recovery.isAvailable ? heroSnapshot.recovery.displayPercent : nil,
            sleepHours: heroSnapshot.sleep.isAvailable ? heroSnapshot.lastSleepHours : nil,
            adherenceRatio: stats.score,
            pendingDoseCount: stats.total - stats.completed,
            nextDoseAbbreviation: next?.peptide.abbreviation,
            nextDoseTimeDisplay: nextTimeDisplay,
            hourOfDay: Calendar.current.component(.hour, from: Date()),
            memberDays: memberDays
        )
    }

    private func coachingFacts(for reason: PrimaryReasonEngine.Reason) -> OnDeviceSummaryEngine.Facts? {
        OnDeviceSummaryEngine.coaching(reason.message, context: buildCoachingContext())
    }

    /// Reconciles coaching, today's dose plan, habits due, and a freshly
    /// changed weekly review into the one top-of-Today reason to act.
    /// `plan` is threaded in from `refreshDerived()` rather than recomputed
    /// so the two stay built from the same `dataStore.todayEntries` pass.
    private func buildPrimaryReason(
        plan: DailyScheduleEngine.DailyPlan,
        habits: HabitsHeroSnapshot
    ) -> PrimaryReasonEngine.Reason {
        let context = PrimaryReasonEngine.Context(
            coaching: buildCoachingContext(),
            dailyPlanHeadline: plan.hasAny ? plan.headline : nil,
            habitsDueCount: habits.dueCount,
            habitsDoneCount: habits.doneCount,
            weeklyReviewHeadline: currentWeeklyReviewChangeHeadline()
        )
        return PrimaryReasonEngine.pick(context: context)
    }

    /// A real, non-noise week-over-week delta for the most recently
    /// generated weekly summary — only when one is actually ready to view
    /// on Today right now. `nil` suppresses the "PROGRESS INSIGHT" tier
    /// entirely rather than ever showing a manufactured trend.
    private func currentWeeklyReviewChangeHeadline() -> String? {
        guard case .ready(let current) = weeklySummaryState else { return nil }
        let previous = dataStore.profile.weeklySummaries.values
            .filter { $0.weekStart != current.weekStart }
            .max { $0.weekStart < $1.weekStart }
        return WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
    }

    /// Rebuilds the hero metric trio snapshot. Adherence is read
    /// synchronously from `todayStats`; Recovery + Sleep round-trip
    /// to HealthKit. Cheap to call — the underlying queries are
    /// cached for short windows by HealthKit itself.
    private func refreshHeroSnapshot() async {
        let snapshot = await HeroMetricSnapshot.build(
            adherenceRatio: adherenceRatio,
            healthConnected: dataStore.profile.healthConnected
        )
        AppAnimation.with(AppAnimation.springSmooth) {
            heroSnapshot = snapshot
            isHeroLoading = false
        }
    }

    /// Builds the Health Monitor grid's personal-range snapshot.
    /// Three HealthKit daily-series queries (HRV / RHR / Sleep) fire
    /// in parallel via async-let. Skips entirely when HealthKit isn't
    /// connected — the grid's empty-state branch hides it.
    private func refreshHealthRange() async {
        guard dataStore.profile.healthConnected else {
            healthRange = .init(hrv: nil, rhr: nil, sleep: nil)
            return
        }
        let previous = healthRange
        healthRange = await HealthRangeService.build()
        // "Sync Complete" only when the refresh brought something new.
        // Firing on any non-empty result announced a sync on every tab
        // return, and stacked on top of an achievement toast.
        let hasData = healthRange.hrv != nil || healthRange.rhr != nil || healthRange.sleep != nil
        defer { if hasData { hasLoadedHealthRange = true } }
        if hasData && hasLoadedHealthRange && healthRange != previous && achievementService.latestUnlock == nil {
            showSyncToast = true
        }
    }

    @ViewBuilder
    private func quickLogSheet(for action: QuickLogAction) -> some View {
        switch action {
        case .meal:
            MealScanFlow(onClose: { quickLogAction = nil })
                .environment(dataStore)
                .liquidGlassPresentation()
        case .dose(let next):
            if let next {
                DoseLoggingSheet(
                    entry: next,
                    lastInjectionSite: next.lastInjectionSite(in: dataStore.entries)
                ) { actualDose, actualTime, site, notes in
                    dataStore.logDose(
                        entryId: next.id,
                        actualDose: actualDose,
                        actualTime: actualTime,
                        injectionSite: site,
                        notes: notes
                    )
                    quickLogAction = nil
                }
                .liquidGlassPresentation()
            } else {
                // `nextDose` was nil at the menu tap (e.g. just
                // logged on the Watch). Show a real "nothing to log"
                // state, not a blank modal.
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing to log",
                    message: "All of today's doses are already logged."
                )
                .padding(Spacing.screenPadding)
                .liquidGlassPresentation()
            }
        }
    }

    /// Whether to surface the weekly recap card on Today. Always
    /// true for Pro users with the toggle on — the card's own
    /// state machine handles the empty/insufficient-data case
    /// gracefully by rendering its `.empty` branch. View layer
    /// reads `WeeklySummaryService.isAvailable(...)` separately
    /// to suppress entirely for free users + opt-outs.
    private var shouldShowWeeklyRecapOnToday: Bool {
        weeklySummaryState != nil
    }

    /// Builds the binding into `profile.weeklySummaries[weekStart]`
    /// the detail view writes back into on refresh. Nil when the
    /// entry has disappeared (deleted between push + render).
    private func bindingForWeeklySummary(weekStart: String) -> Binding<WeeklySummary>? {
        guard dataStore.profile.weeklySummaries[weekStart] != nil else { return nil }
        return Binding(
            get: { dataStore.profile.weeklySummaries[weekStart] ?? .placeholder(weekStart: weekStart) },
            set: { newValue in
                dataStore.profile.weeklySummaries[weekStart] = newValue
                dataStore.persistProfile()
            }
        )
    }

    /// Loads (or refreshes) the current-week summary. Suppresses
    /// the card entirely when the user isn't Pro + opted-in. Routes
    /// through `WeeklySummaryService` so the Pro gate, opt-out gate,
    /// network call, cache, and offline fallback all stay in one
    /// place. Returns the loaded summary's kind, or nil when none was
    /// produced.
    @discardableResult
    private func loadWeeklySummary(forceRefresh: Bool) async -> WeeklySummary.Kind? {
        guard WeeklySummaryService.shared.isAvailable(profile: dataStore.profile) else {
            weeklySummaryState = nil
            return nil
        }

        // Cached value short-circuits unless the caller asked for a
        // refresh — but only when its source fingerprint still matches
        // the week's current data. A summary generated before the user
        // edited a dose/meal/lab within the same week falls through to
        // `generate(...)`, which regenerates. Synchronous read so the
        // .ready state lands before `generate(...)` returns.
        if !forceRefresh, let cached = WeeklySummaryService.shared.cachedIfFresh(
            profile: dataStore.profile,
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            workoutDates: dataStore.recentWorkoutDates()
        ) {
            weeklySummaryState = .ready(cached)
            return cached.kind
        }

        // The week's data changed since the recap was generated. Keep the
        // stale recap on screen and regenerate it in the background, at
        // most every few hours, instead of a shimmer plus an AI request
        // on every Today appear after each log.
        var isRefreshingStale = false
        if !forceRefresh,
           let stale = WeeklySummaryService.shared.cached(in: dataStore.profile, for: Date()) {
            weeklySummaryState = .ready(stale)
            guard WeeklySummaryService.isDueForRegeneration(stale) else { return stale.kind }
            isRefreshingStale = true
        }

        if !isRefreshingStale { weeklySummaryState = .loading }
        do {
            // Pull a fresh HRV series each refresh — cheaper than
            // caching it on the @State, and the user is unlikely to
            // refresh more than once per minute.
            let hrv = dataStore.profile.healthConnected
                ? await HealthKitService.shared.dailyHRV(days: 21)
                : []
            let summary = try await WeeklySummaryService.shared.generate(
                profile: dataStore.profile,
                protocols: dataStore.protocols,
                entries: dataStore.entries,
                workoutDates: dataStore.recentWorkoutDates(),
                hrvSeries: hrv,
                // Pass a stable category code rather than the
                // free-text title — the title can embed details about
                // dose timing / protocol count that the aggregate's
                // privacy contract says we never send. The proxy
                // model has the numeric fields to infer the situation.
                topInsightCategory: dataStore.topInsight.map { insight in
                    switch insight.type {
                    case .positive: return "positive"
                    case .warning:  return "warning"
                    case .neutral:  return "neutral"
                    }
                },
                forceRefresh: forceRefresh
            )
            WeeklySummaryService.shared.record(summary, in: &dataStore.profile)
            dataStore.persistProfile()
            weeklySummaryState = .ready(summary)
            return summary.kind
        } catch WeeklySummaryService.GenerationError.insufficientData {
            weeklySummaryState = .empty
            return nil
        } catch {
            if !isRefreshingStale { weeklySummaryState = .failed }
            return nil
        }
    }

    private func isCurrentWeek(_ weekStart: String) -> Bool {
        WeeklySummaryService.shared.cached(in: dataStore.profile, for: Date())?.weekStart == weekStart
    }

    /// Honours the `peptidex://weekly/current` deep-link. Sets the
    /// detail-push target to the most recent cached summary, or
    /// triggers a generation if nothing is cached yet.
    private func consumeWeeklyDeepLink() {
        guard appState.pendingWeeklyRecap else { return }
        appState.pendingWeeklyRecap = false

        let latest = dataStore.profile.weeklySummaries
            .values
            .max(by: { $0.weekStart < $1.weekStart })
        if let latest {
            detailWeekStart = latest.weekStart
        } else {
            Task { await loadWeeklySummary(forceRefresh: true) }
        }
    }

    /// Honours the deep-link UUID parked by the Live Activity tap
    /// handler in `PeptideApp.onOpenURL`. Resolves the matching
    /// entry and presents the same `DoseLoggingSheet` the user
    /// would see from a row tap. Cleared after consumption so a
    /// re-appear (e.g. switching tabs back) doesn't re-present.
    private func consumePendingDoseDeepLink() {
        guard let pendingId = appState.pendingDoseLogEntryId else { return }
        appState.pendingDoseLogEntryId = nil
        guard let entry = dataStore.entries.first(where: { $0.id == pendingId })
        else { return }
        selectedEntry = entry
    }

    /// Surfaces the next pending Day-7 / Day-30 / cycle-complete prompt
    /// when Home becomes visible. Skipped when another sheet is already
    /// up so we never stack modals on top of each other.
    ///
    /// Cycle-completion prompts (Plan A: an `.active` protocol whose
    /// cycle window ended) take priority over share milestones — the
    /// user has to resolve state-transition decisions before we ask
    /// them to share. Only one prompt fires per Home appear.
    private func checkMilestonePrompt() {
        // TabView can call onAppear for retained, off-screen tabs during
        // modal transitions. A Today prompt must never replace Train's
        // workout cover or completion summary.
        guard appState.selectedTab == .today,
              milestonePrompt == nil,
              milestoneShareProtocol == nil,
              completionPrompt == nil
        else { return }

        // Run the auto-completion sweep BEFORE deciding which prompt
        // to fire. A user who never backgrounds the app (scene-phase
        // .active never re-triggers) but switches between tabs would
        // otherwise see a prompt for a protocol the next foreground
        // would have silently auto-completed — three buttons that
        // all apply to a soon-to-be-completed cycle. Running the
        // sweep here too keeps the two surfaces consistent.
        dataStore.performCycleAutoCompletion()
        CycleCompletionService.shared.pruneState(keeping: dataStore.protocols)
        CycleMilestoneService.shared.pruneSuppression(keeping: dataStore.protocols)

        // Completion prompt wins when present.
        if let pending = CycleCompletionService.shared.pendingCompletion(in: dataStore.protocols) {
            let days = max(0, daysPastCycleEnd(of: pending))
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard appState.selectedTab == .today, completionPrompt == nil else { return }
                completionPrompt = CompletionPromptItem(proto: pending, daysPastEnd: days)
            }
            return
        }

        guard let pending = CycleMilestoneService.shared.pendingMilestone(in: dataStore.protocols) else {
            return
        }
        // Defer slightly so the home tab's appear animation lands first.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard appState.selectedTab == .today, milestonePrompt == nil else { return }
            milestonePrompt = MilestonePromptItem(proto: pending.proto, milestone: pending.milestone)
        }
    }

    private func daysPastCycleEnd(of proto: PeptideProtocol) -> Int {
        // Reads `cycleEndDay` (the model's single source of truth)
        // so this surface stays in lockstep with CycleCompletionService.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return cal.dateComponents([.day], from: proto.cycleEndDay, to: today).day ?? 0
    }

    private struct CompletionPromptItem: Identifiable {
        let proto: PeptideProtocol
        let daysPastEnd: Int
        var id: String { "\(proto.id.uuidString):\(Int(proto.startDate.timeIntervalSince1970))" }
    }

    private struct MilestonePromptItem: Identifiable {
        let proto: PeptideProtocol
        let milestone: CycleMilestoneService.Milestone
        var id: String { "\(proto.id.uuidString):\(milestone.rawValue)" }
    }

    // The "Create your first protocol" empty state moved to the
    // Library tab (PeptideListView) — protocol creation now lives
    // alongside the peptide database there, so Today stays focused
    // on the day's signals rather than onboarding chrome.

    // Stack-warning + stack-adjustment helpers moved to
    // ProtocolsStackHealthSection in Phase 34 alongside the cards
    // that called them.

    /// First-name token for the sticky header. Trimmed +
    /// space-split so "Alex Chen" reads as "Hi, Alex". Empty
    /// string is handled by the sticky header's own fallback so
    /// this helper stays a pure transform.
    private var firstNameForSticky: String {
        dataStore.profile.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        case 17..<24: return String(localized: "Good evening")
        default: return String(localized: "Up late")
        }
    }

    private var dateString: String {
        selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

#Preview("With Data") {
    HomeView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    HomeView()
        .environment(DataStore())
        .environment(AppState())
        .preferredColorScheme(.dark)
}
