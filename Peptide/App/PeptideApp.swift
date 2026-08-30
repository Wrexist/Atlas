import SwiftUI
import UserNotifications
import CoreSpotlight
import RevenueCat

@main
struct PeptideApp: App {
    @State private var appState = AppState()
    @State private var dataStore: DataStore
    @State private var localization = LocalizationManager.shared
    @State private var themeManager = ThemeManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var notificationDelegate: NotificationDelegate?
    /// Holds the Darwin-notification observer that listens for
    /// widget-extension "Log dose" intent taps. Lifetime tied to
    /// the app's WindowGroup — released only on app termination.
    @State private var pendingDoseLogToken: PendingDoseLogProcessor.ObservationToken?
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var travelChange: TimezoneChangeDetector.Change?
    /// Drives the "What's New" splash. Set on first launch after
    /// an update, cleared once the user finishes the tour.
    @State private var showWhatsNewTour: Bool = false

    init() {
        // RevenueCat observes the app's own StoreKit 2 purchases here
        // (StoreService / PaywallView keep their existing purchase flow
        // untouched) so the dashboard, webhooks, and entitlement
        // analytics stay accurate without changing what actually
        // charges the user. Must run before any StoreKit product or
        // purchase call, so it's the first thing App.init() does.
        Purchases.logLevel = .warn
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: "appl_PnJfoICofSeTSftseVMMMnonafC")
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )

        // SwiftUI's `AsyncImage` reads through `URLCache.shared`. The
        // default cap is ~5 MB memory / 20 MB disk, which gets evicted
        // before the food library's 25-row search results finish
        // scrolling. Bump it generously up-front so OFF product
        // thumbnails (typically 5-20 KB each) survive across a
        // search session and across sheet open/close cycles — saves
        // bandwidth on a metered connection and makes the list
        // perceptibly faster on a re-open.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,    // 50 MB resident
            diskCapacity:   200 * 1024 * 1024,   // 200 MB on disk
            diskPath:       "peptidex-imagecache"
        )

        #if DEBUG
        // Fail loudly if a photoreal anatomy pack ships with any muscle
        // mask missing — see docs/PHOTOREAL_ANATOMY_PLAN.md. No-op until
        // the base body images are bundled.
        AnatomyAssets.auditCoverage()
        #endif

        // App.init() may be nonisolated in strict Swift 6 mode; assumeIsolated
        // bridges to @MainActor safely since @main always runs on the main thread.
        _dataStore = State(wrappedValue: MainActor.assumeIsolated {
            MigrationService.shared.migrateIfNeeded()
            let store = DataStore()
            WatchSyncService.shared.onMarkComplete = { entryId, _ in
                store.markEntryComplete(entryId)
            }
            WatchSyncService.shared.onMarkIncomplete = { entryId, _ in
                store.markEntryIncomplete(entryId)
            }
            WatchSyncService.shared.onLogWater = { oz in
                store.logWater(oz: oz)
            }
            // Resolve haptics against the live profile so the global
            // "Haptic Feedback" toggle is honoured everywhere without
            // threading it through each view.
            Haptics.configure { [weak store] in
                store?.profile.hapticFeedbackEnabled ?? true
            }
            return store
        })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                        .environment(dataStore)
                        .preferredColorScheme(themeManager.displayMode.preferredScheme)
                        .tint(AppColor.accentPrimary)
                } else if dataStore.profile.biometricLockEnabled, !isUnlocked {
                    LockScreenView { isUnlocked = true }
                        .environment(dataStore)
                        .preferredColorScheme(themeManager.displayMode.preferredScheme)
                        .tint(AppColor.accentPrimary)
                } else {
                    mainContent
                }
            }
            .environment(localization)
            .environment(\.locale, localization.effectiveLocale)
            .environment(\.layoutDirection, localization.layoutDirection)
            .id(localization.selectedCode ?? "system")
            .task {
                // One-shot Spotlight reindex on app start. Custom foods
                // and favorites stay in sync via DataStore mutation
                // hooks, but a fresh install or a CloudKit pull on a
                // second device needs this to seed the index — without
                // it, the user wouldn't see their library in Spotlight
                // until they next edited a food.
                dataStore.reindexFoodSpotlight()
            }
            .task {
                // Subscribe to MetricKit so crash + hang + disk-write
                // payloads delivered the day after a problem occurs
                // are captured locally. Apple's TestFlight dashboard
                // already gets these on the server side; the local
                // copy is the foundation for a future
                // Diagnostics-in-Profile screen and eventual backend
                // upload. Idempotent — subscribing on every launch
                // is the documented usage.
                DiagnosticsService.shared.startCollecting()
            }
            .task {
                // Drain any completed onboarding funnel snapshot to the
                // analytics endpoint configured via Info.plist. No-op
                // unless the endpoint is configured, the user opted in
                // via the Profile diagnostics toggle, AND onboarding
                // finished — partial in-flight runs stay local.
                await OnboardingFunnelTracker.drainIfReady()
            }
            .task {
                // Drain any local affiliate application to the creator-
                // program intake endpoint. Same opt-in shape as the
                // funnel drain — gated on AffiliateIntakeEndpoint in
                // Info.plist, no-op otherwise. The local copy stays
                // on disk regardless so the user can re-edit.
                await AffiliateIntakeService.drainIfReady(
                    dataStore.profile.affiliateApplication
                )
            }
            .onOpenURL { url in
                // All `peptidex://` routing lives in DeepLinkRouter so
                // the widget / Live Activity / notification link
                // vocabulary is one tested mapping instead of an
                // inline switch per entry point.
                DeepLinkRouter.route(url, appState: appState)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                // Spotlight tapped a food index entry. Parse the
                // namespaced identifier (`peptidex-food/custom/<uuid>`
                // for user-defined foods, `peptidex-food/off/<barcode>`
                // for OFF favorites), stash the result on AppState,
                // and switch to the Today tab so the meals section
                // (HomeMealsSection) picks it up. Unknown formats
                // are dropped silently — better to no-op than to
                // surface a confusing error to a user who tapped a
                // Spotlight tile expecting their food to open.
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let deepLink = FoodLogDeepLink(spotlightIdentifier: identifier)
                else { return }
                // Phase D: food handoff now lands on the dedicated
                // Meals tab so the receiver of `pendingFoodLogID`
                // (the meals section's `.onChange`) doesn't race the
                // mirror mount still on Today.
                appState.selectedTab = .meals
                appState.pendingFoodLogID = deepLink
            }
            .sheet(item: $travelChange) { change in
                TravelModePromptSheet(
                    change: change,
                    exampleShift: travelExampleShift(for: change),
                    onShift: {
                        dataStore.applyTravelShift(
                            toTimezone: change.currentIdentifier,
                            hoursDelta: change.hoursDelta
                        )
                        travelChange = nil
                    },
                    onKeep: {
                        dataStore.acknowledgeTimezone(change.currentIdentifier)
                        travelChange = nil
                    }
                )
            }
            .sheet(isPresented: $showWhatsNewTour) {
                // Full-screen, drag-to-dismiss disabled — the tour
                // is a deliberate one-time read, not an
                // afterthought sheet. Swipe-down would otherwise
                // dismiss before the user reaches the "Get
                // started" button on the last page, and the
                // version stamp wouldn't land — they'd see it
                // again on the next launch.
                WhatsNewTourSheet(
                    pages: WhatsNewPage.v30Training,
                    onComplete: {
                        WhatsNewService.shared.markCurrentTourSeen()
                        showWhatsNewTour = false
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if dataStore.profile.biometricLockEnabled {
                    isUnlocked = false
                }
                // Flush any debounced save before the OS suspends us, so a
                // burst of dose toggles right before backgrounding doesn't
                // get lost.
                dataStore.flushPendingSave()
            }
            if phase == .active {
                ReviewPromptService.shared.recordLaunch()
                dataStore.handleAppActivation()
                // Re-check StoreKit entitlements so a subscription
                // that lapsed while the app was suspended flips
                // `isProUser` off. The `Transaction.updates` stream
                // only fires for incoming transactions; an expiry
                // produces no transaction, so the cached
                // entitlement would otherwise stay true until the
                // user manually purchased again.
                Task { await StoreService.shared.checkProAccess() }
                // Re-check notification authorization. If the user
                // revoked permission in iOS Settings while the app
                // was suspended, the local `doseRemindersEnabled`
                // flag stays true and `scheduleNotifications` would
                // silently no-op forever. Flip the flag so the UI
                // surfaces the inconsistency.
                Task { @MainActor in
                    let status = await NotificationService.shared.checkAuthorization()
                    if status == .denied && dataStore.profile.doseRemindersEnabled {
                        dataStore.profile.doseRemindersEnabled = false
                        dataStore.persistProfile()
                    }
                }
                // Drain any "user tapped Log on the Live Activity"
                // markers the widget extension queued while we were
                // suspended. Runs before reconcile so the just-
                // logged entries are flagged completed and the
                // reconcile pass dismisses their live activities in
                // the same scene-phase tick.
                PendingDoseLogProcessor.drain(into: dataStore)
                // Re-evaluate which scheduled doses are in their
                // active window so the lock-screen Live Activities
                // start / end without needing the user to open the
                // app to a specific tab.
                DoseLiveActivityService.shared.reconcile(entries: dataStore.entries)
                // Re-reconcile the Sunday weekly-recap notification
                // on every active transition — handles "user toggled
                // opt-out elsewhere", "user upgraded to Pro", and
                // "permission status changed in Settings".
                Task { @MainActor in
                    await WeeklySummaryNotificationScheduler.reconcile(
                        profile: dataStore.profile,
                        isPro: StoreService.shared.isProUser
                    )
                }
                detectTimezoneChange()
                maybePresentWhatsNewTour()
            }
        }
    }

    /// Presents the "What's New" tour exactly once per version
    /// bump for existing users. Fresh installs (i.e. users who
    /// haven't finished onboarding yet) are excluded — the
    /// regular onboarding flow already covers the basics, and
    /// double-stacking sheets at first launch would feel
    /// overwhelming. A small delay lets any other launch-time
    /// sheet (Live Activity reconcile, biometric unlock) settle
    /// first so the tour reads as the headline event, not a
    /// jump-cut.
    private func maybePresentWhatsNewTour() {
        // First-launch bootstrap: stamp the current version on a
        // brand-new install so the post-onboarding launch doesn't
        // double up with a tour the regular onboarding already
        // covered. Idempotent after the first stamp.
        WhatsNewService.shared.bootstrapForFreshInstallIfNeeded(
            hasCompletedOnboarding: hasCompletedOnboarding
        )

        guard !showWhatsNewTour,
              WhatsNewService.shared.shouldShowTour(hasCompletedOnboarding: hasCompletedOnboarding)
        else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            // Re-check inside the Task — another launch in the
            // same scene tick could have already presented the
            // sheet, and we don't want a double-present race.
            guard !showWhatsNewTour else { return }
            showWhatsNewTour = true
        }
    }

    /// One-shot travel detection on every transition to `.active`.
    /// Reads the user's last-known zone from `dataStore.profile`,
    /// hands it to `TimezoneChangeDetector`, and sets
    /// `travelChange` (which drives the prompt sheet) only on a
    /// real crossing. On a fresh install (no previous identifier)
    /// we silently record the current zone so the next launch has
    /// a baseline to compare against.
    private func detectTimezoneChange() {
        let stored = dataStore.profile.lastKnownTimezoneIdentifier
        if stored == nil {
            dataStore.acknowledgeTimezone(TimeZone.current.identifier)
            return
        }
        if let change = TimezoneChangeDetector.detect(previousIdentifier: stored) {
            travelChange = change
        }
    }

    /// First active protocol's first preferred time, paired with
    /// what it would shift to under the proposed delta. Returns
    /// nil when the user has no active protocols (the prompt is
    /// still useful — they can apply the shift before adding any).
    private func travelExampleShift(
        for change: TimezoneChangeDetector.Change
    ) -> (original: String, shifted: String)? {
        guard let firstActive = dataStore.activeProtocols.first,
              let firstTime = firstActive.schedule.preferredTimes.first
        else { return nil }
        let shifted = TravelModeLogic.shiftTime(firstTime, byHours: change.hoursDelta)
        return (firstTime, shifted)
    }

    private var coreTabView: some View {
        TabView(selection: $appState.selectedTab) {
            Tab("Today", systemImage: "house.fill", value: .today) {
                HomeContainerView()
            }
            Tab("Train", systemImage: "dumbbell.fill", value: .train) {
                TrainContainerView()
            }
            Tab("Meals", systemImage: "fork.knife", value: .meals) {
                MealsContainerView()
            }
            Tab("Biology", systemImage: "heart.fill", value: .biology) {
                BiologyView()
            }
            Tab("Habits", systemImage: "star.fill", value: .habits) {
                HabitsView()
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            Haptics.selection()
        }
    }

    @ViewBuilder
    private var tabViewWithAccessory: some View {
        if #available(iOS 26.0, *) {
            coreTabView.tabViewBottomAccessory {
                TabAccessoryView(tab: appState.selectedTab)
            }
        } else {
            coreTabView
        }
    }

    private var mainContent: some View {
        tabViewWithAccessory
        .safeAreaInset(edge: .top, spacing: 0) {
            // Persistent data-loss banner. Previously the only
            // `lastError` surfaces were inside Onboarding and the
            // Profile account section, so a user who landed on Today
            // never saw a "changes won't be saved" warning.
            PersistenceErrorBanner(message: dataStore.lastError)
                .animation(.spring(response: 0.4, dampingFraction: 0.85),
                           value: dataStore.lastError)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Floating "you're in screenshot mode" reminder sits
            // above the tab bar while ScreenshotMode is on. Self-
            // hides via internal `if` when the toggle is off, so
            // this inset costs nothing in production.
            ScreenshotModeBanner()
                .animation(.spring(response: 0.4, dampingFraction: 0.85),
                           value: ScreenshotMode.shared.isEnabled)
        }
        .environment(appState)
        .environment(dataStore)
        .preferredColorScheme(themeManager.displayMode.preferredScheme)
        .tint(AppColor.accentPrimary)
        .overlay {
            // App-wide celebration presenter — confetti for habit
            // completions, the level-up overlay for the Atlas Score — so a
            // win celebrates on whichever tab the user is on.
            CelebrationHostView()
        }
        // Single Profile sheet shared by every tab's avatar button, so
        // settings/account are reachable without returning to Today.
        .sheet(isPresented: Bindable(appState).showProfile) {
            ProfileView()
                .environment(dataStore)
                .environment(appState)
        }
        // Demoted peptide Library (database + Protocols + AI research) —
        // promoted Habits took its tab slot, so it opens as a full-screen
        // modal from Today's cycle pill and the Profile entries.
        .fullScreenCover(isPresented: Bindable(appState).showLibrary) {
            PeptideListView(presentedModally: true)
                .environment(dataStore)
                .environment(appState)
        }
        .task {
            let delegate = NotificationDelegate(dataStore: dataStore, appState: appState)
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
            NotificationService.shared.registerCategories()

            // Register the Darwin-notification observer once per
            // scene. The token is stored on `pendingDoseLogToken`
            // for lifetime ownership — releasing it removes the
            // observer.
            if pendingDoseLogToken == nil {
                pendingDoseLogToken = PendingDoseLogProcessor.startObserving(dataStore)
            }

            // Repopulate the in-memory ID tracker from iOS's actual pending
            // requests. Without this, force-quit leaves orphan reminders that
            // scheduleNotifications can't see in its set-diff and won't remove.
            await NotificationService.shared.reconcilePendingState()

            // Habit reminders are gated per-habit (Habit.reminderTime), not
            // by `doseRemindersEnabled`. Re-stamp them every activation so a
            // reminderTime change made on another device propagates.
            NotificationService.shared.scheduleHabitReminders(for: dataStore.activeHabits)

            guard dataStore.profile.doseRemindersEnabled else {
                NotificationService.shared.cancelProtocolReminders()
                return
            }

            let status = await NotificationService.shared.checkAuthorization()
            if status == .notDetermined {
                let granted = await NotificationService.shared.requestAuthorization()
                if !granted {
                    dataStore.profile.doseRemindersEnabled = false
                    dataStore.persistProfile()
                    NotificationService.shared.cancelProtocolReminders()
                    return
                }
            } else if status == .denied {
                dataStore.profile.doseRemindersEnabled = false
                dataStore.persistProfile()
                NotificationService.shared.cancelProtocolReminders()
                return
            }

            NotificationService.shared.scheduleNotifications(for: dataStore.activeProtocols)
        }
    }
}

/// The strip above the tab bar. It answers "is today done?" for whatever
/// the user is currently looking at — workouts on Train, doses everywhere
/// else — because a dose reminder under the muscle map is answering a
/// question nobody on that screen asked.
struct TabAccessoryView: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .train:
            WorkoutAccessoryView()
        case .today, .meals, .biology, .habits:
            NextDoseAccessoryView()
        }
    }
}

/// Train's counterpart to `NextDoseAccessoryView`. The session count is
/// held in state rather than read in `body`: `workoutSummary` faults
/// SwiftData, and the accessory re-renders on every tab change.
struct WorkoutAccessoryView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var sessionService = WorkoutSessionService.shared
    @State private var loggedToday = 0

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppColor.accentPrimary)
                .contentTransition(.symbolEffect(.replace))
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .animation(AppAnimation.springSnappy, value: loggedToday)
        .accessibilityElement(children: .combine)
        .task(id: dataStore.revision) {
            loggedToday = dataStore.workoutSummary().count
        }
    }

    private var icon: String {
        if sessionService.activeSession != nil { return "figure.run" }
        return loggedToday > 0 ? "checkmark.circle.fill" : "dumbbell.fill"
    }

    private var label: LocalizedStringKey {
        if sessionService.activeSession != nil { return "Workout in progress" }
        return loggedToday > 0
            ? "All workouts logged for today"
            : "No workout logged yet today"
    }
}

struct NextDoseAccessoryView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        let allDone = dataStore.nextDose == nil

        HStack(spacing: Spacing.sm) {
            Image(systemName: allDone ? "checkmark.circle.fill" : "syringe.fill")
                .font(.caption)
                .foregroundStyle(AppColor.accentPrimary)
                .contentTransition(.symbolEffect(.replace))

            if let next = dataStore.nextDose {
                Text("Next: \(next.peptide.abbreviation) \u{2022} \(next.dose)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(next.date.formatted(.dateTime.hour().minute()))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentLight)
                    .contentTransition(.numericText())
            } else {
                Text("All doses completed for today")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .animation(AppAnimation.springSnappy, value: allDone)
    }
}

/// App-wide banner for persistence failures (fallback store at launch
/// or a failed live save). Renders nothing when `message` is nil.
struct PersistenceErrorBanner: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.15))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: \(message)")
        }
    }
}
