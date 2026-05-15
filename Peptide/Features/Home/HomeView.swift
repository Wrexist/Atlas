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
                            if dataStore.profile.hapticFeedbackEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            showProfileCustomization = true
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
                            withAnimation(AppAnimation.springSnappy) {
                                appState.selectedTab = .protocols
                            }
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
                        onQuickLog: { showQuickLogMenu() },
                        hapticsEnabled: dataStore.profile.hapticFeedbackEnabled
                    )
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

                    // Bevel-style hero trio — Adherence / Recovery /
                    // Sleep. Replaces the single-ring "score" model
                    // with three at-a-glance numbers that map to the
                    // user's mental model from Whoop / Oura / Bevel.
                    HeroMetricTrio(
                        snapshot: heroSnapshot,
                        onTapRing: { kind in
                            if dataStore.profile.hapticFeedbackEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            heroDetailKind = HeroDetailItem(kind: kind)
                        },
                        hapticsEnabled: dataStore.profile.hapticFeedbackEnabled
                    )
                    .sectionAppear(index: 0)

                    // Coaching line — turns the trio's three numbers
                    // into a single recommendation. Same priority
                    // cascade Bevel uses ("Excellent recovery, push
                    // today" / "Short sleep, cap intensity"), tuned
                    // for Atlas's peptide-protocol context.
                    CoachingCard(message: coachingMessage)
                        .sectionAppear(index: 0)

                    if overview.hasAnySignal {
                        TodayOverviewCard(
                            snapshot: overview,
                            hapticsEnabled: dataStore.profile.hapticFeedbackEnabled,
                            onTapHero: { dose in
                                guard let dose else { return }
                                selectedEntry = dose
                            },
                            onTapInsight: { insight in
                                if case .latestLab = insight {
                                    appState.pendingLabsOpen = true
                                    appState.selectedTab = .insights
                                }
                            }
                        )
                        .sectionAppear(index: 0)
                    }

                    if dataStore.protocols.isEmpty {
                        gettingStartedCard
                            .sectionAppear(index: 1)
                    } else {
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

                    HomeMealsSection()
                        .id(TodayJumpBar.SectionAnchor.meals)
                        .sectionAppear(index: 2)

                    if !dataStore.protocols.isEmpty {
                        DailyPlanCard(
                            plan: dailyPlan,
                            onTapDose: { entry in selectedEntry = entry }
                        )
                        .id(TodayJumpBar.SectionAnchor.doses)
                        .sectionAppear(index: 3)

                        TodayScheduleCard(
                            entries: stats.entries,
                            onToggle: { entry in dataStore.toggleEntry(entry.id) },
                            onTap: { entry in selectedEntry = entry }
                        )
                        .sectionAppear(index: 3)

                        QuickStatsRow(
                            activeProtocols: dataStore.activeProtocols.count,
                            daysLogged: dataStore.totalDaysLogged,
                            compliance: Int(dataStore.averageCompliance * 100),
                            nextDose: dataStore.nextDose
                        )
                        .sectionAppear(index: 4)
                    }

                    HomeWellnessSection()
                        .id(TodayJumpBar.SectionAnchor.wellness)
                        .sectionAppear(index: 5)

                    HomeMovementSection()
                        .id(TodayJumpBar.SectionAnchor.movement)
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
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeStickyHeader(
                    firstName: firstNameForSticky,
                    avatarImageData: dataStore.profile.avatarImageData,
                    onAvatarTap: {
                        if dataStore.profile.hapticFeedbackEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        showProfileCustomization = true
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
            .sheet(item: $milestonePrompt) { item in
                CycleMilestonePromptSheet(
                    proto: item.proto,
                    milestone: item.milestone,
                    onShare: {
                        CycleMilestoneService.shared.markShown(item.milestone, for: item.proto.id)
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
                        CycleMilestoneService.shared.markShown(item.milestone, for: item.proto.id)
                        milestonePrompt = nil
                    }
                )
                .liquidGlassPresentation(detents: [.medium])
            }
            .sheet(item: $milestoneShareProtocol) { proto in
                ShareCardSheet(subject: .singleProtocol(proto))
                    .environment(dataStore)
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
            .onChange(of: stats.score) { oldScore, newScore in
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
            // Re-fetch the hero trio whenever today's adherence ratio
            // shifts (a dose was logged/unlogged) so the Adherence
            // ring reflects the action without waiting for a scene-
            // phase round-trip.
            .onChange(of: stats.score) { _, _ in
                Task { await refreshHeroSnapshot() }
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
    /// `.insights` jumps to the Insights tab via `AppState`; every
    /// other anchor scrolls within Today's existing `ScrollViewReader`.
    private func handleJump(to anchor: TodayJumpBar.SectionAnchor, proxy: ScrollViewProxy) {
        switch anchor {
        case .insights:
            withAnimation(AppAnimation.springSnappy) {
                appState.selectedTab = .insights
            }
        case .doses, .meals, .wellness, .movement:
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
        let workoutsToday = dataStore.profile.workoutHistory.filter { entry in
            cal.isDate(entry.date, inSameDayAs: now)
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
            hourOfDay: Calendar.current.component(.hour, from: Date())
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
                EmptyView()
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
                topInsight: dataStore.topInsight?.title,
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
    private func checkMilestonePrompt() {
        guard milestonePrompt == nil,
              milestoneShareProtocol == nil,
              !showProfileCustomization
        else { return }

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

    private struct MilestonePromptItem: Identifiable {
        let proto: PeptideProtocol
        let milestone: CycleMilestoneService.Milestone
        var id: String { "\(proto.id.uuidString):\(milestone.rawValue)" }
    }

    private var gettingStartedCard: some View {
        EmptyStateView(
            icon: "flask.fill",
            title: "Create your first protocol",
            message: "Set up a peptide protocol to start tracking doses, streaks, and compliance.",
            action: .init(title: "Get started", icon: "plus") {
                withAnimation(AppAnimation.springSnappy) {
                    appState.selectedTab = .protocols
                }
            },
            secondary: .init(title: "Browse the library", icon: "magnifyingglass") {
                withAnimation(AppAnimation.springSnappy) {
                    appState.selectedTab = .library
                }
            }
        )
    }

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
