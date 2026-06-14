import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var selectedEntry: ProtocolEntry?
    @State private var showAchievementToast = false
    @State private var toastAchievement: Achievement?
    @State private var achievementService = AchievementService.shared
    /// Observed directly so the notification banner reacts to a fresh
    /// schedule report. DataStore exposes `notificationReport` as a passthrough,
    /// but a computed read from a non-observed singleton wouldn't re-render
    /// the View on its own.
    @State private var notificationService = NotificationService.shared
    @State private var showProfileCustomization = false
    /// Drives the calorie/macro targets editor presented from the
    /// Today overview card's "Set a calorie target" nudge — previously
    /// the nudge was tappable but wired to nothing.
    @State private var showTargetsEditor = false
    // Profile is opened via the shared `appState.showProfile` flag now
    // (a single app-level sheet), so the Today avatar and every other
    // tab's avatar button route through the same presentation.
    /// 0…1 fade progress for the sticky compressing header. Driven
    /// by `.onScrollGeometryChange` so the bar materialises in lock-
    /// step with the user's finger.
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
    /// Tracks which jump-bar section is currently nearest the top of
    /// the viewport so the corresponding chip highlights. Driven by
    /// per-section preference reads in `.onScrollGeometryChange` —
    /// effectively free since the scroll geometry callback is already
    /// firing for the sticky-header progress.
    @State private var activeJumpAnchor: TodayJumpBar.SectionAnchor? = .doses
    /// Routes the chip-bar "+ Log" button. The dialog flag controls
    /// the picker; the action enum drives which sheet actually mounts.
    @State private var showQuickLogDialog = false
    @State private var quickLogAction: QuickLogAction?
    /// Bevel-style hero metric trio snapshot. Loaded async on first
    /// appear + on each .active scene transition so the rings reflect
    /// the freshest HealthKit reads without blocking the view body.
    @State private var heroSnapshot: HeroMetricSnapshot = .empty
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
    @Environment(\.requestReview) private var requestReview

    private struct HeroDetailItem: Identifiable {
        let kind: HeroMetricKind
        var id: HeroMetricKind { kind }
    }

    private enum QuickLogAction: Identifiable {
        case meal, dose
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

    private var dailyPlan: DailyScheduleEngine.DailyPlan {
        DailyScheduleEngine.plan(for: dataStore.todayEntries)
    }

    /// Touches `notificationService.lastReport` so the View takes a SwiftUI
    /// observation dependency on it — without this, the dependency is on
    /// DataStore.notificationReport which reads a non-observed singleton
    /// and so the banner won't refresh after a reschedule.
    private var shouldShowNotificationBanner: Bool {
        notificationService.lastReport.hasAnyIssue
    }

    var body: some View {
        let stats = todayStats
        let overview = TodayOverviewSnapshot.build(from: dataStore)

        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xl) {
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

                    // Bevel-style twin context pills — current cycle
                    // status on the left (tap → Protocols tab), date
                    // on the right. Glanceable context without
                    // claiming a full section.
                    TodayContextRow(
                        activeProtocol: dataStore.activeProtocols.first,
                        date: Date(),
                        onTapCycle: {
                            // Library is no longer a tab — open it as a
                            // modal with the protocol list pending so the
                            // cycle pill still lands on Protocols in one hop.
                            appState.pendingProtocolList = true
                            appState.showLibrary = true
                        }
                    )
                    .sectionAppear(index: 0)

                    // Quick-jump chips — sits below the greeting so the
                    // user reaches Meals / Wellness / Movement / the
                    // Insights tab in one tap instead of scrolling past
                    // the day-at-a-glance, score, plan, and schedule
                    // cards. Also hosts the "+ Log" quick-log Menu so
                    // primary log actions are reachable from above the
                    // fold.
                    TodayJumpBar(
                        activeAnchor: activeJumpAnchor,
                        showsDoses: !dataStore.protocols.isEmpty,
                        onSelect: { anchor in handleJump(to: anchor, proxy: proxy) },
                        onQuickLog: { showQuickLogMenu() }
                    )
                    .sectionAppear(index: 0)

                    // Habit-first hero — today's habits, the daily completion
                    // ring, the active streak, and the Atlas Score lead the
                    // screen so the user's daily wins are the first thing they
                    // see and act on. Per-habit summary work is snapshotted
                    // off-body inside the component (audit A6).
                    TodayHabitsHero()
                        .sectionAppear(index: 0)

                    // Observed via the @State notificationService so the banner
                    // re-renders when a reschedule writes a fresh report. Reading
                    // through DataStore's passthrough wouldn't trigger redraw.
                    if shouldShowNotificationBanner,
                       let report = dataStore.notificationReport {
                        NotificationIssueBanner(
                            report: report,
                            droppedProtocolNames: dataStore.droppedReminderProtocolNames
                        )
                        .sectionAppear(index: 0)
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
                        .sectionAppear(index: 0)
                    }

                    // Labeled section, mirroring the headered Wellness /
                    // Movement / Timeline / Health blocks further down so
                    // the whole scroll reads as consistent, navigable
                    // chunks instead of an unlabeled wall of cards.
                    HomeSectionHeader(eyebrow: "Today", title: "At a glance")
                        .sectionAppear(index: 0)

                    // Bevel-style hero trio — Adherence / Recovery /
                    // Sleep. Replaces the single-ring "score" model
                    // with three at-a-glance numbers that map to the
                    // user's mental model from Whoop / Oura / Bevel.
                    HeroMetricTrio(
                        snapshot: heroSnapshot,
                        onTapRing: { kind in
                            Haptics.impact(.light)
                            heroDetailKind = HeroDetailItem(kind: kind)
                        }
                    )
                    .sectionAppear(index: 0)

                    // Coaching line — turns the trio's three numbers
                    // into a single recommendation. Same priority
                    // cascade Bevel uses ("Excellent recovery, push
                    // today" / "Short sleep, cap intensity"), tuned
                    // for Atlas's peptide-protocol context.
                    CoachingCard(message: coachingMessage)
                        .sectionAppear(index: 0)

                    // Momentum — goal projection. Habits now lead the screen
                    // in TodayHabitsHero above; the goal countdown stays here
                    // for users who committed to a target date. Guarded so the
                    // header never sits alone when no goal date is set.
                    if dataStore.profile.goalDate != nil {
                        HomeSectionHeader(eyebrow: "Momentum", title: "Your goal")
                            .sectionAppear(index: 0)

                        GoalCountdownCard(
                            goalDate: dataStore.profile.goalDate,
                            primaryGoal: dataStore.profile.primaryGoal
                        )
                        .sectionAppear(index: 0)
                    }

                    if overview.hasAnySignal {
                        TodayOverviewCard(
                            snapshot: overview,
                            onTapHero: { dose in
                                guard let dose else { return }
                                selectedEntry = dose
                            },
                            onTapInsight: { insight in
                                switch insight {
                                case .latestLab:
                                    appState.pendingLabsOpen = true
                                    appState.selectedTab = .biology
                                case .nudge(_, _, _, .setCalorieTarget):
                                    showTargetsEditor = true
                                case .nudge(_, _, _, .logMeal):
                                    appState.selectedTab = .meals
                                case .protocolInsight, .nudge:
                                    break
                                }
                            }
                        )
                        .sectionAppear(index: 0)
                    }

                    // Protocol creation now lives on the Library tab —
                    // Today no longer shows the full-screen "Create your
                    // first protocol" card for new users. Once a protocol
                    // exists, the score card surfaces here as before.
                    if !dataStore.protocols.isEmpty {
                        HomeSectionHeader(eyebrow: "Protocols", title: "Today's doses")
                            .sectionAppear(index: 1)

                        ProtocolScoreCard(
                            score: stats.score,
                            completed: stats.completed,
                            total: stats.total,
                            streak: dataStore.currentStreak,
                            bestStreak: dataStore.bestStreak,
                            weeklyCompletion: dataStore.weeklyCompletion
                        )
                        .sectionAppear(index: 1)
                    }

                    // MARK: - Meals / Wellness / Movement
                    //
                    // Meals is the most-used surface on Today, so it
                    // sits ABOVE the dose plan/schedule cards now —
                    // users reached for it most and were scrolling
                    // past four cards to get there. Doses are still
                    // surfaced in TodayOverviewCard's hero, and the
                    // jump chips above reach the full schedule in
                    // one tap.

                    // HomeMealsSection used to render on the Today scroll
                    // AND inside MealsContainerView. Spotlight taps with
                    // a recipe deep-link fired sheets in both mounts
                    // simultaneously (audit Meals MED 10). Removed from
                    // Today; the dedicated Meals tab is the single
                    // owner. The jump-bar .meals chip now navigates to
                    // the Meals tab (handled in handleJump).

                    if !dataStore.protocols.isEmpty {
                        DailyPlanCard(
                            plan: dailyPlan,
                            onTapDose: { entry in selectedEntry = entry }
                        )
                        .id(TodayJumpBar.SectionAnchor.doses)
                        .trackSectionAnchor(.doses)
                        .sectionAppear(index: 3)

                        TodayScheduleCard(
                            entries: stats.entries,
                            onToggle: { entry in dataStore.toggleEntry(entry.id) },
                            onTap: { entry in selectedEntry = entry }
                        )
                        .sectionAppear(index: 3)

                        // QuickStatsRow removed in the declutter pass —
                        // its compliance figure duplicated ProtocolScoreCard
                        // and its "next dose" duplicated the tab-bar bottom
                        // accessory, so it was noise rather than signal.
                    }

                    HomeWellnessSection()
                        .id(TodayJumpBar.SectionAnchor.wellness)
                        .trackSectionAnchor(.wellness)
                        .sectionAppear(index: 5)

                    HomeMovementSection()
                        .id(TodayJumpBar.SectionAnchor.movement)
                        .trackSectionAnchor(.movement)
                        .sectionAppear(index: 5)

                    // Bevel-style chronological feed — doses + meals
                    // + check-in + workouts merged into one sorted
                    // list. Hides itself when the day has no events
                    // (a brand-new install before the first log).
                    TodayTimelineCard(events: timelineEvents)
                        .sectionAppear(index: 6)

                    // Bevel-style Health Monitor grid — HRV / RHR /
                    // Sleep with personal-range indicators. Hides
                    // individual cards (or the whole grid) when
                    // there's not enough HealthKit history to render
                    // a meaningful range.
                    HealthMonitorGrid(snapshot: healthRange)
                        .sectionAppear(index: 7)

                    // The standalone bottom insight card used to live
                    // here; removed in this pass because TodayOverviewCard
                    // already surfaces the same `dataStore.topInsight`
                    // (via TodayOverviewSnapshot.pickBottomInsight) at the
                    // top of the scroll. Showing it twice was duplication,
                    // not depth.
                }
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
                    progress: stickyProgress
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
            // Stack-warning / stack-adjustment / paywall sheets
            // moved to ProtocolsStackHealthSection in Phase 34 —
            // their host cards live on the Protocols tab now, so
            // chaining the sheets there avoids a cross-tab modal
            // dance.
            .sheet(isPresented: $showProfileCustomization) {
                ProfileCustomizationSheet()
                    .environment(dataStore)
                    .environment(appState)
                    .liquidGlassPresentation()
            }
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
                        CycleMilestoneService.shared.markShown(item.milestone, for: item.proto)
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
                    onDismiss: {
                        CycleMilestoneService.shared.markShown(item.milestone, for: item.proto)
                        milestonePrompt = nil
                    }
                )
                .liquidGlassPresentation(detents: [.medium])
            }
            .sheet(item: $completionPrompt) { item in
                CycleCompletionPromptSheet(
                    proto: item.proto,
                    daysPastEnd: item.daysPastEnd,
                    onMarkComplete: {
                        dataStore.updateProtocolStatus(id: item.proto.id, to: .completed)
                        CycleCompletionService.shared.markAutoCompleted(item.proto)
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
                        dataStore.extendProtocol(id: item.proto.id, byWeeks: 2)
                        completionPrompt = nil
                    },
                    onStartNewCycle: {
                        // Mark BEFORE restarting so the suppression key
                        // is recorded against the pre-restart startDate
                        // (the cycle that actually ended).
                        CycleCompletionService.shared.markAutoCompleted(item.proto)
                        dataStore.restartProtocol(id: item.proto.id)
                        completionPrompt = nil
                    },
                    onDismiss: {
                        CycleCompletionService.shared.recordDismissal(for: item.proto)
                        completionPrompt = nil
                    }
                )
                .liquidGlassPresentation(detents: [.medium, .large])
            }
            .sheet(item: $milestoneShareProtocol) { proto in
                ShareCardSheet(subject: .singleProtocol(proto))
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .navigationDestination(for: Peptide.self) { peptide in
                PeptideDetailView(peptide: peptide)
            }
            .overlay {
                if let achievement = toastAchievement {
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
                    withAnimation(AppAnimation.springBouncy) { showAchievementToast = true }
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
            // Single handler for adherence-ratio changes: refresh the
            // hero trio so the Adherence ring reflects a logged/unlogged
            // dose immediately, and fire the review prompt when the day
            // first hits 100%. Previously two separate `onChange(of:
            // stats.score)` modifiers spawned two async tasks per toggle.
            .onChange(of: stats.score) { oldScore, newScore in
                Task { await refreshHeroSnapshot() }
                if oldScore < 1.0, newScore >= 1.0, stats.total > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
                    }
                }
            }
            .onAppear {
                checkMilestonePrompt()
                consumePendingDoseDeepLink()
                consumeWeeklyDeepLink()
                Task { await loadWeeklySummary(forceRefresh: false) }
                Task { await refreshHeroSnapshot() }
                Task { await refreshHealthRange() }
            }
            .onChange(of: appState.pendingDoseLogEntryId) { _, _ in
                consumePendingDoseDeepLink()
            }
            .onChange(of: appState.pendingWeeklyRecap) { _, _ in
                consumeWeeklyDeepLink()
            }
            .navigationDestination(item: $detailWeekStart) { weekStart in
                if let binding = bindingForWeeklySummary(weekStart: weekStart) {
                    WeeklySummaryDetailView(
                        summary: binding,
                        onRefresh: { await loadWeeklySummary(forceRefresh: true) }
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
                        lastSleepHours: heroSnapshot.lastSleepHours,
                        sleepTargetHours: 8.0
                    )
                )
                .liquidGlassPresentation()
            }
            .confirmationDialog(
                "Quick log",
                isPresented: $showQuickLogDialog,
                titleVisibility: .visible
            ) {
                Button("Snap a meal photo") { quickLogAction = .meal }
                if dataStore.nextDose != nil {
                    Button("Log next dose") { quickLogAction = .dose }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Capture something without scrolling.")
            }
            }   // closes ScrollViewReader
        }
    }

    // MARK: - Quick-log routing

    /// Routes a jump-bar chip tap to a scroll target or a tab switch.
    /// `.biology` jumps to the Biology tab via `AppState`; every
    /// other anchor scrolls within Today's existing `ScrollViewReader`.
    private func handleJump(to anchor: TodayJumpBar.SectionAnchor, proxy: ScrollViewProxy) {
        switch anchor {
        case .biology:
            withAnimation(AppAnimation.springSnappy) {
                appState.selectedTab = .biology
            }
        case .meals:
            // Meals lives on its own tab now (audit Meals MED 10).
            // The Today scroll no longer mounts HomeMealsSection so
            // scrolling here would be a no-op — switch tab instead.
            withAnimation(AppAnimation.springSnappy) {
                appState.selectedTab = .meals
            }
        case .doses, .wellness, .movement:
            withAnimation(.smooth(duration: 0.35)) {
                proxy.scrollTo(anchor, anchor: .top)
            }
            activeJumpAnchor = anchor
        }
    }

    private func showQuickLogMenu() {
        showQuickLogDialog = true
    }

    /// Today's chronological event feed for `TodayTimelineCard`.
    /// Pulls doses + meals + check-in + workouts and hands them
    /// to the pure `TodayTimelineEvent.build` for sorting + row
    /// construction. Recomputes cheaply on every body re-eval
    /// (small lists, all in-memory).
    private var timelineEvents: [TodayTimelineEvent] {
        let now = Date()
        let cal = Calendar.current
        // Plan C: workouts now live in StoredWorkoutSession; the
        // timeline still expects the legacy `WorkoutEntry` shape, so
        // adapt at this boundary. Mirrors the converter on
        // `WorkoutDetailView.entryFromSession`. Empty-exercise quick-
        // log sessions still render — the timeline only needs name +
        // date + duration.
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let workoutsToday: [WorkoutEntry] = SwiftDataRepository.shared
            .loadWorkoutSessions(startedBetween: dayStart..<dayEnd)
            .map { session in
                let sets = session.exercises.flatMap(\.sets)
                let reps = sets.reduce(0) { $0 + $1.reps }
                let avgReps = sets.isEmpty ? 0 : reps / sets.count
                let duration: Int = {
                    guard let finished = session.finishedAt else { return 0 }
                    return max(0, Int(finished.timeIntervalSince(session.startedAt) / 60))
                }()
                return WorkoutEntry(
                    id: session.id,
                    date: session.startedAt,
                    name: session.name ?? "Workout",
                    sets: sets.count,
                    reps: avgReps,
                    durationMinutes: duration
                )
            }
        return TodayTimelineEvent.build(
            doses: dataStore.todayEntries,
            meals: dataStore.mealEntries(),
            checkIn: dataStore.outcome(),
            workouts: workoutsToday,
            now: now
        )
    }

    /// Builds the coaching context from the current store + hero
    /// snapshot. Pure read — synchronous so the view body can
    /// consume it without an async hop.
    private var coachingMessage: CoachingMessageEngine.CoachingMessage {
        let next = dataStore.nextDose
        let nextTimeDisplay: String? = next.map {
            DateFormatter.localizedString(from: $0.date, dateStyle: .none, timeStyle: .short)
        }
        let memberDays = Calendar.current
            .dateComponents([.day], from: dataStore.profile.memberSince, to: Date())
            .day ?? 0
        let context = CoachingMessageEngine.Context(
            hasProtocols: !dataStore.protocols.isEmpty,
            healthConnected: dataStore.profile.healthConnected,
            recoveryScore: heroSnapshot.recovery.isAvailable ? heroSnapshot.recovery.displayPercent : nil,
            sleepHours: heroSnapshot.sleep.isAvailable
                ? Double(heroSnapshot.sleep.displayPercent) / 100 * 8.0    // approx; 8h target
                : nil,
            adherenceRatio: todayStats.score,
            pendingDoseCount: todayStats.total - todayStats.completed,
            nextDoseAbbreviation: next?.peptide.abbreviation,
            nextDoseTimeDisplay: nextTimeDisplay,
            hourOfDay: Calendar.current.component(.hour, from: Date()),
            memberDays: memberDays
        )
        return CoachingMessageEngine.pick(context: context)
    }

    /// Rebuilds the hero metric trio snapshot. Adherence is read
    /// synchronously from `todayStats`; Recovery + Sleep round-trip
    /// to HealthKit. Cheap to call — the underlying queries are
    /// cached for short windows by HealthKit itself.
    private func refreshHeroSnapshot() async {
        let snapshot = await HeroMetricSnapshot.build(
            adherenceRatio: todayStats.score,
            healthConnected: dataStore.profile.healthConnected
        )
        heroSnapshot = snapshot
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
        healthRange = await HealthRangeService.build()
        // Surface the Bevel-style "Sync Complete" toast only when the
        // refresh actually produced at least one card — avoids the
        // false-positive of "synced!" on a brand-new install that
        // has no HealthKit data yet.
        if healthRange.hrv != nil || healthRange.rhr != nil || healthRange.sleep != nil {
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
        case .dose:
            if let next = dataStore.nextDose {
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
                // `nextDose` can go nil between the dialog tap and the
                // sheet mounting (e.g. logged on the Watch). Show a
                // real "nothing to log" state, not a blank modal.
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

        // Cached value short-circuits unless the caller asked for
        // a refresh. `cached(in:for:)` is a synchronous read so the
        // .ready state lands before `generate(...)` returns.
        if !forceRefresh, let cached = WeeklySummaryService.shared.cached(
            in: dataStore.profile, for: Date()
        ) {
            weeklySummaryState = .ready(cached)
            return
        }

        weeklySummaryState = .loading
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
            weeklySummaryState = .empty
        }
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
        guard milestonePrompt == nil,
              milestoneShareProtocol == nil,
              completionPrompt == nil,
              !showProfileCustomization
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
                guard completionPrompt == nil else { return }
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
            guard milestonePrompt == nil else { return }
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
        case 17..<22: return "Good evening"
        default: return "Good night"
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
