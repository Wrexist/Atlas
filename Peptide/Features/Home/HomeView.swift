import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var selectedEntry: ProtocolEntry?
    @State private var showAchievementToast = false
    @State private var toastAchievement: Achievement?
    @State private var achievementService = AchievementService.shared
    @State private var celebrationCenter = CelebrationCenter.shared
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
    /// Routes the chip-bar "+ Log" button. The sheet flag controls
    /// the picker; the action enum drives which sheet actually mounts.
    @State private var showQuickLogSheet = false
    @State private var quickLogAction: QuickLogAction?
    @State private var showWeightSheet = false
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
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    /// Start of the calendar day Today is showing. Re-synced on midnight,
    /// time-zone changes and every foreground, so the derived models and
    /// the habits hero roll over even when nothing else mutates the store.
    @State private var displayedDay = Calendar.current.startOfDay(for: .now)

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
        /// Finished sessions this calendar week — the trio's first ring
        /// for a user with no active protocol.
        var workoutsThisWeek = 0
        /// Today's session count and minutes — feeds the Movement card
        /// without a fetch from `body`.
        var workoutSummary: (count: Int, minutes: Int) = (0, 0)
        /// The logging checklist. Filters the full meal and weight
        /// histories, so it's built here rather than in `body`.
        var checklist: TodayChecklistEngine.State?
    }

    private struct HeroDetailItem: Identifiable {
        let kind: HeroMetricKind
        var id: HeroMetricKind { kind }
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

    private static let reviewWorthyAchievements: Set<String> = [
        "streak_7", "streak_14", "streak_30", "streak_90",
        "fifty_doses", "hundred_doses", "five_hundred_doses",
        "month_logged"
    ]

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

    /// Recomputes the derived Today models. Cheap enough to run
    /// synchronously on the main actor — it's a handful of in-memory passes
    /// plus one week-scoped SwiftData fetch — but it must not run from `body`.
    private func refreshDerived() {
        let plan = DailyScheduleEngine.plan(for: dataStore.todayEntries)
        let habits = HabitsHeroSnapshot.build(
            activeHabits: dataStore.activeHabits,
            entries: dataStore.profile.habitEntries,
            frozenDayKeys: dataStore.profile.streakFreezeDays
        )
        let weekSessions = finishedWorkoutSessionsThisWeek()
        let todaySessions = weekSessions.filter { Calendar.current.isDateInToday($0.startedAt) }
        let workoutSummary = (
            count: todaySessions.count,
            minutes: todaySessions.reduce(0) { $0 + $1.elapsedSeconds() / 60 }
        )
        let next = DerivedToday(
            overview: TodayOverviewSnapshot.build(from: dataStore),
            plan: plan,
            timeline: buildTimelineEvents(workoutSessions: todaySessions),
            primaryReason: buildPrimaryReason(plan: plan, habits: habits),
            habits: habits,
            workoutsThisWeek: weekSessions.count,
            workoutSummary: workoutSummary,
            checklist: TodayChecklistEngine.state(
                profile: dataStore.profile,
                consumption: dataStore.consumption(),
                trainedToday: workoutSummary.count > 0
            )
        )
        // Inside an animation so the cards' numericText digits roll.
        AppAnimation.with(AppAnimation.springSmooth) { derived = next }
    }

    /// Rolls Today over to the current calendar day (re-keying the derived
    /// models when it changed) and re-reads the HealthKit-backed rings, which
    /// can move without any store mutation — overnight sleep, a new HRV sample.
    private func syncDisplayedDay() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != displayedDay { displayedDay = today }
        Task { await refreshHeroSnapshot() }
        Task { await refreshHealthRange() }
    }

    /// The week's finished sessions — one fetch that also covers today, so
    /// the weekly count, Movement summary and timeline share it.
    private func finishedWorkoutSessionsThisWeek() -> [WorkoutSession] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return SwiftDataRepository.shared
            .loadWorkoutSessions(startedBetween: week.start..<week.end)
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
                    TodayJumpBar(
                        activeAnchor: activeJumpAnchor,
                        showsDoses: showsDoseSection,
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

                    // Observed via the @State notificationService so the banner
                    // re-renders when a reschedule writes a fresh report. Reading
                    // through DataStore's passthrough wouldn't trigger redraw.
                    if shouldShowNotificationBanner,
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

                    // PRIMARY STATUS. Hide the adherence/recovery/sleep
                    // trio for a brand-new user with no protocols and no
                    // Health connection — all zeros read as failure
                    // (roadmap day-0). They lead with the habit hero
                    // below; the trio's footer offers Connect Health.
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

                    // PRIMARY RECOMMENDATION — the one thing
                    // `PrimaryReasonEngine` ranked highest across
                    // recovery/sleep coaching, today's dose plan, habits
                    // due, and a freshly-changed weekly review. Same
                    // single-card discipline Bevel uses ("Excellent
                    // recovery, push today" / "Short sleep, cap
                    // intensity") — just reconciled across more signals
                    // than coaching alone used to see.
                    if let reason = derived.primaryReason {
                        // Keyed on the title so a new recommendation
                        // cross-fades in rather than swapping text in place.
                        CoachingCard(message: reason.message)
                            .id(reason.message.title)
                            .transition(.opacity.combined(with: .scale(0.98)))
                            .sectionAppear(index: 3)
                    }

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

                    // PRIMARY ACTION — today's habits, the daily
                    // completion ring, and the active streak. Per-habit
                    // summary work is snapshotted off-body inside the
                    // component (audit A6).
                    TodayHabitsHero(snapshot: derived.habits)
                        .sectionAppear(index: 4)

                    // The day's logging loop in one card — every open
                    // row is also the shortcut that closes it.
                    if let checklist = derived.checklist {
                        TodayChecklistCard(
                            state: checklist,
                            unit: dataStore.profile.bodyMetrics.unit,
                            onAction: handleChecklistAction
                        )
                        .sectionAppear(index: 5)
                    }

                    if showsDoseSection, let plan = derived.plan {
                        // The ONE place doses appear on Today — the
                        // overview card and the timeline leave them out.
                        // The header's Manage button is the labeled
                        // Library entry that replaced the removed cycle pill.
                        VStack(spacing: Spacing.sm) {
                            HomeSectionHeader(eyebrow: "Protocols", title: "Today's doses") {
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
                        }
                        .id(TodayJumpBar.SectionAnchor.doses)
                        .trackSectionAnchor(.doses)
                        .scrollReveal()
                    }

                    HomeWellnessSection()
                        .id(TodayJumpBar.SectionAnchor.wellness)
                        .trackSectionAnchor(.wellness)
                        .scrollReveal()

                    HomeMovementSection(summary: derived.workoutSummary)
                        .id(TodayJumpBar.SectionAnchor.movement)
                        .trackSectionAnchor(.movement)
                        .scrollReveal()

                    // ANALYSIS from here down — glanceable summaries the
                    // user pulls up on demand, after every actionable
                    // section above (Product Architecture 07).

                    // Lifestyle overview: calorie / streak / check-in /
                    // water grid and the rotating insight.
                    if let overview = derived.overview, overview.hasAnySignal {
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
                            onTapTile: { tile in handleOverviewTile(tile, proxy: proxy) }
                        )
                        .scrollReveal()
                    }

                    // Momentum — goal countdown for users who committed
                    // to a target date, and the earned Atlas Score
                    // (level / tier / progress). Guarded so the header
                    // never sits alone when the card has nothing to show.
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

                    // The AI research chat's only other entry is an icon
                    // in the Library toolbar. Pro opens the chat; free
                    // users see the paywall for it from the root.
                    ResearchAssistantRow {
                        if StoreService.shared.isProUser {
                            showResearchAssistant = true
                        } else {
                            appState.presentedPaywall = .aiResearch
                        }
                    }
                    .scrollReveal()

                    // Protocol tracking is an optional advanced feature,
                    // so with zero protocols its entry sits down here
                    // with the other explore rows rather than above the
                    // training and nutrition sections. Still one labeled
                    // row, so the Library stays findable from Today.
                    if dataStore.protocols.isEmpty {
                        ProtocolsDiscoverRow {
                            appState.pendingProtocolList = true
                            appState.showLibrary = true
                        }
                        .scrollReveal()
                    }

                    // Bevel-style chronological feed — meals, check-in
                    // and workouts merged into one sorted list (doses
                    // stay in their own section above). Hides itself
                    // when the day has no events (a brand-new install
                    // before the first log).
                    TodayTimelineCard(
                        events: derived.timeline,
                        onTap: { event in handleTimelineTap(event, proxy: proxy) }
                    )
                    .scrollReveal()

                    // Bevel-style Health Monitor grid — HRV / RHR /
                    // Sleep with personal-range indicators. Hides
                    // individual cards (or the whole grid) when
                    // there's not enough HealthKit history to render
                    // a meaningful range.
                    HealthMonitorGrid(snapshot: healthRange)
                        .scrollReveal()

                    // The standalone bottom insight card used to live
                    // here; removed in this pass because TodayOverviewCard
                    // already surfaces the same `dataStore.topInsight`
                    // (via TodayOverviewSnapshot.pickBottomInsight) at the
                    // top of the scroll. Showing it twice was duplication,
                    // not depth.
                }
                .appAnimation(AppAnimation.toast, value: shouldShowNotificationBanner)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                // Cap content width on iPad / landscape — without this
                // the cards stretch the full screen and the long-form
                // copy reads as awkward 80-character lines (audit
                // Phase 5.8 partial). 640pt keeps a comfortable
                // readable measure; the rest gets centered.
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
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
            // Scroll-tracked jump-bar active anchor. Each tagged
            // section publishes its frame via SectionAnchorFrameKey;
            // ActiveSectionPicker reduces the dictionary to the
            // anchor whose top edge is closest to (but not past)
            // the header inset. Only writes when the picked anchor
            // actually changes — keeps the chip-bar from re-
            // rendering on every scroll tick.
            .coordinateSpace(name: "HomeScroll")
            .onPreferenceChange(SectionAnchorFrameKey.self) { frames in
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
                DoseLoggingSheet(entry: entry) { actualDose, actualTime, site, notes in
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
            .overlay {
                if celebrationCenter.current == nil, let achievement = toastAchievement {
                    AchievementToastView(achievement: achievement, isShowing: $showAchievementToast)
                }
            }
            .overlay(alignment: .top) {
                // Bevel-style sync-complete pill. The toast manages
                // its own auto-dismiss timer (2.4s) so we just bind
                // the visibility flag and forget about it.
                SyncToast(isShowing: $showSyncToast)
                    .padding(.top, Spacing.sm)
            }
            .onChange(of: achievementService.latestUnlock?.id) { _, newId in
                if let newId, let achievement = achievementService.achievements.first(where: { $0.id == newId }) {
                    toastAchievement = achievement
                    AppAnimation.with(AppAnimation.springBouncy) { showAchievementToast = true }
                    if Self.reviewWorthyAchievements.contains(newId) {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
                        }
                    }
                }
            }
            .onChange(of: showAchievementToast) { _, isShowing in
                // Drain one queued unlock when its toast finishes —
                // this surfaces the next pending unlock (if a single
                // save crossed several milestones) instead of all but
                // the last being dropped.
                if !isShowing { achievementService.acknowledgeLatestUnlock() }
            }
            // Single handler for adherence-ratio changes: update only the
            // trio's Adherence ring so a logged/unlogged dose shows
            // immediately without re-reading HealthKit, and fire the
            // review prompt when the day first hits 100%.
            .onChange(of: stats.score) { oldScore, newScore in
                let ratio = adherenceRatio
                AppAnimation.with(AppAnimation.springSmooth) {
                    heroSnapshot = heroSnapshot.withAdherence(ratio)
                }
                if oldScore < 1.0, newScore >= 1.0, stats.total > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
                    }
                }
            }
            // Recompute the derived Today models once per store mutation.
            // `.task(id:)` cancels and re-runs on each new revision, and fires
            // once on first appear, which covers the initial population too.
            .task(id: dataStore.revision) {
                refreshDerived()
            }
            .onChange(of: displayedDay) { _, _ in refreshDerived() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { syncDisplayedDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                syncDisplayedDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                syncDisplayedDay()
            }
            // The coaching copy reads recovery + sleep off the hero snapshot,
            // so it has to re-pick when that lands (it arrives async, after
            // the first `refreshDerived()`).
            .onChange(of: heroSnapshot) { _, _ in
                let plan = derived.plan ?? DailyScheduleEngine.plan(for: dataStore.todayEntries)
                let reason = buildPrimaryReason(plan: plan, habits: derived.habits)
                AppAnimation.with(AppAnimation.springSmooth) { derived.primaryReason = reason }
            }
            .onAppear {
                checkMilestonePrompt()
                consumePendingDoseDeepLink()
                consumeWeeklyDeepLink()
                Task { await loadWeeklySummary(forceRefresh: false) }
                Task { await refreshHeroSnapshot() }
                Task { await refreshHealthRange() }
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
                            : nil
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
        activeJumpAnchor = anchor
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
            let glass = TodayChecklistEngine.glassFluidOunces(for: dataStore.profile.bodyMetrics.unit)
            dataStore.logWater(fluidOunces: glass)
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
    /// taken; un-checking keeps the store's own soft tap.
    private func toggleDose(_ entry: ProtocolEntry) {
        if !entry.completed { Haptics.success() }
        AppAnimation.with(AppAnimation.springSnappy) { dataStore.toggleEntry(entry.id) }
    }

    private func handleChecklistAction(_ item: TodayChecklistEngine.Item) {
        switch item {
        case .meals:
            quickLogAction = .meal
        case .training:
            appState.selectedTab = .train
        case .water:
            let glass = TodayChecklistEngine.glassFluidOunces(for: dataStore.profile.bodyMetrics.unit)
            dataStore.logWater(fluidOunces: glass)
        case .weight:
            showWeightSheet = true
        }
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

    /// Today's chronological event feed for `TodayTimelineCard`.
    /// Pulls meals + check-in + today's finished workouts and hands them
    /// to the pure `TodayTimelineEvent.build` for sorting + row
    /// construction.
    private func buildTimelineEvents(workoutSessions: [WorkoutSession]) -> [TodayTimelineEvent] {
        // Plan C: workouts now live in StoredWorkoutSession; the
        // timeline still expects the legacy `WorkoutEntry` shape, so
        // adapt at this boundary. Empty-exercise quick-log sessions
        // still render — the timeline only needs name + date +
        // duration.
        let workoutsToday: [WorkoutEntry] = workoutSessions
            .map { session in
                let sets = session.exercises.flatMap(\.sets)
                let reps = sets.reduce(0) { $0 + $1.reps }
                let avgReps = sets.isEmpty ? 0 : reps / sets.count
                return WorkoutEntry(
                    id: session.id,
                    date: session.startedAt,
                    name: session.name ?? "Workout",
                    sets: sets.count,
                    reps: avgReps,
                    durationMinutes: session.elapsedSeconds() / 60
                )
            }
        return TodayTimelineEvent.build(
            meals: dataStore.mealEntries(),
            checkIn: dataStore.outcome(),
            workouts: workoutsToday
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
        if hasData && healthRange != previous && !showAchievementToast {
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
                DoseLoggingSheet(entry: next) { actualDose, actualTime, site, notes in
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
    /// place.
    private func loadWeeklySummary(forceRefresh: Bool) async {
        guard WeeklySummaryService.shared.isAvailable(profile: dataStore.profile) else {
            weeklySummaryState = nil
            return
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
            entries: dataStore.entries
        ) {
            weeklySummaryState = .ready(cached)
            return
        }

        // The week's data changed since the recap was generated. Keep the
        // stale recap on screen and regenerate it in the background, at
        // most every few hours, instead of a shimmer plus an AI request
        // on every Today appear after each log.
        var isRefreshingStale = false
        if !forceRefresh,
           let stale = WeeklySummaryService.shared.cached(in: dataStore.profile, for: Date()) {
            weeklySummaryState = .ready(stale)
            guard WeeklySummaryService.isDueForRegeneration(stale) else { return }
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
        } catch WeeklySummaryService.GenerationError.insufficientData {
            weeklySummaryState = .empty
        } catch {
            if !isRefreshingStale { weeklySummaryState = .failed }
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
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<24: return "Good evening"
        default: return "Up late"
        }
    }

    private var dateString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
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
