import SwiftUI
import UIKit
import UserNotifications
import CoreSpotlight
import RevenueCat

@main
struct PeptideApp: App {
    @UIApplicationDelegateAdaptor(AtlasAppDelegate.self) private var appDelegate
    @State private var appState: AppState
    @State private var dataStore: DataStore
    @State private var localization = LocalizationManager.shared
    @State private var themeManager = ThemeManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// `UNUserNotificationCenter` holds its delegate weakly; this keeps it
    /// alive for the process.
    @State private var notificationDelegate: NotificationDelegate
    @State private var quickActionInbox = QuickActionInbox.shared
    @State private var isUnlocked = false
    @State private var showLockReleasedNotice = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var travelChange: TimezoneChangeDetector.Change?
    /// Drives the "What's New" splash. Set on first launch after
    /// an update, cleared once the user finishes the tour.
    @State private var showWhatsNewTour: Bool = false
    /// Guard the one-shot launch and notification work against the
    /// language switch's `.id` rebuild of the root tree.
    @State private var hasStartedLaunchWork = false
    @State private var hasStartedNotificationSync = false

    init() {
        // RevenueCat observes the app's own StoreKit 2 purchases here
        // (StoreService / PaywallView keep their existing purchase flow
        // untouched) so the dashboard, webhooks, and entitlement
        // analytics stay accurate without changing what actually
        // charges the user. Must run before any StoreKit product or
        // purchase call, so it's the first thing App.init() does.
        // Skipped under unit tests so StoreServiceTests' sandbox purchases
        // never reach the live RevenueCat project.
        if !ProcessInfo.processInfo.isRunningUnitTests {
            Purchases.logLevel = .warn
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: "appl_PnJfoICofSeTSftseVMMMnonafC")
                    .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                    .build()
            )
        }

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
            directory:      URL.cachesDirectory.appending(path: "peptidex-imagecache")
        )

        // App.init() may be nonisolated in strict Swift 6 mode; assumeIsolated
        // bridges to @MainActor safely since @main always runs on the main thread.
        let launch = MainActor.assumeIsolated {
            MigrationService.shared.migrateIfNeeded()
            let store = DataStore()
            WatchSyncService.shared.onMarkComplete = { entryId, _, takenAt in
                store.markEntryComplete(entryId, at: takenAt)
            }
            WatchSyncService.shared.onMarkIncomplete = { entryId, _ in
                store.markEntryIncomplete(entryId)
            }
            WatchSyncService.shared.onLogWater = { fluidOunces, date in
                store.logWater(fluidOunces: fluidOunces, date: date)
            }
            // Resolve haptics against the live profile so the global
            // "Haptic feedback" toggle is honoured everywhere without
            // threading it through each view.
            Haptics.configure { [weak store] in
                store?.profile.hapticFeedbackEnabled ?? true
            }
            // The delegate must be in place before launch finishes, or
            // iOS drops the response that launched the app: a "Mark as
            // Taken" or weight reply that cold-starts Atlas, often in the
            // background where no scene (and no view task) ever builds.
            let appState = AppState()
            let delegate = NotificationDelegate(dataStore: store, appState: appState)
            UNUserNotificationCenter.current().delegate = delegate
            NotificationService.shared.registerCategories()
            // Unlocked whenever the lock is off, so turning it on from
            // Profile doesn't raise the lock screen over the toggle's own
            // Face ID check (B014). Held locked while an account change
            // keeps the real profile from loading.
            let startsUnlocked = !store.profile.biometricLockEnabled && !store.isAwaitingCloudAccountDecision
            return (store: store, appState: appState, notificationDelegate: delegate, startsUnlocked: startsUnlocked)
        }
        _dataStore = State(wrappedValue: launch.store)
        _appState = State(wrappedValue: launch.appState)
        _notificationDelegate = State(wrappedValue: launch.notificationDelegate)
        _isUnlocked = State(wrappedValue: launch.startsUnlocked)
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.isRunningUnitTests {
                // Unit tests are hosted in the app. A bare window keeps
                // them clear of `appRoot`'s launch tasks — App Attest,
                // MetricKit, Spotlight and notification prompts.
                Color.clear
            } else {
                appRoot
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !ProcessInfo.processInfo.isRunningUnitTests else { return }
            if phase == .background {
                if dataStore.profile.biometricLockEnabled {
                    isUnlocked = false
                }
                // Flush any debounced save before the OS suspends us, so a
                // burst of dose toggles right before backgrounding doesn't
                // get lost.
                dataStore.flushPendingSave()
                // Leaving the app is the moment a just-logged meal, weigh-
                // in, workout or habit should cancel today's matching
                // reminder, and the rolling one-shot window moves forward.
                // Held open as a background task: reconcile removes stale
                // reminders before adding their replacements, and a
                // suspension in between would leave none until next open.
                let backgroundTask = BackgroundTaskHandle(name: "Reminder reconcile")
                Task { @MainActor in
                    await DailyReminderScheduler.reconcile(dataStore: dataStore)
                    await dataStore.rescheduleHabitReminders()
                    backgroundTask.end()
                }
            }
            if phase == .active {
                UpsellScheduler.recordActiveDay()
                dataStore.handleAppActivation()
                // Re-check notification authorization. If the user
                // revoked permission in iOS Settings while the app
                // was suspended, the local `doseRemindersEnabled`
                // flag stays true and `scheduleNotifications` would
                // silently no-op forever. Flip the flag so the UI
                // surfaces the inconsistency. Otherwise re-plan doses,
                // which refills the every-N-days lookahead as its
                // one-shots fire, then habits, which roll their window
                // forward and step past the fresh dose slots.
                Task { @MainActor in
                    let status = await NotificationService.shared.checkAuthorization()
                    if status == .denied && dataStore.profile.doseRemindersEnabled {
                        dataStore.profile.doseRemindersEnabled = false
                        dataStore.persistProfile()
                    } else if status != .denied {
                        dataStore.rescheduleNotificationsIfEnabled()
                    }
                    await dataStore.rescheduleHabitReminders()
                }
                // Drain any "user tapped Log on the Live Activity"
                // markers the widget extension queued while we were
                // suspended. Runs before reconcile so the just-
                // logged entries are flagged completed and the
                // reconcile pass dismisses their live activities in
                // the same scene-phase tick.
                PendingDoseLogProcessor.drain(into: dataStore)
                QuickActionRouter.drainPendingWater(into: dataStore)
                WorkoutActivityActionProcessor.drain()
                // After the drain, so a set ticked on the lock screen
                // counts as activity before staleness is judged.
                WorkoutSessionService.shared.closeIfStale()
                // Starts the workout's activity if Live Activities were
                // switched on, or a start failed, since the workout began.
                WorkoutLiveActivityService.shared.reconcile(active: WorkoutSessionService.shared.activeSession)
                // Re-evaluate which scheduled doses are in their
                // active window so the lock-screen Live Activities
                // start / end without needing the user to open the
                // app to a specific tab.
                dataStore.reconcileDoseLiveActivities()
                // Re-check StoreKit entitlements so a subscription
                // that lapsed while the app was suspended flips
                // `isProUser` off — an expiry produces no transaction
                // on `Transaction.updates`. Then re-reconcile the Sunday
                // weekly recap against the fresh answer: it handles
                // "user toggled opt-out elsewhere", "user upgraded to
                // Pro" and "permission status changed in Settings", and
                // reading `isProUser` before the scan finished cancelled
                // every Pro user's recap on a cold launch.
                Task { @MainActor in
                    await StoreService.shared.checkProAccess()
                    await WeeklySummaryNotificationScheduler.reconcile(
                        dataStore: dataStore,
                        isPro: StoreService.shared.isProUser
                    )
                    await DailyReminderScheduler.reconcile(dataStore: dataStore)
                }
                detectTimezoneChange()
                maybePresentWhatsNewTour()
                maybePresentWinBack()
            }
        }
    }

    private var appRoot: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .environment(dataStore)
                    .preferredColorScheme(themeManager.displayMode.preferredScheme)
                    .tint(AppColor.accentPrimary)
            } else {
                // Stays mounted while locked — the lock covers it from
                // its own window — so open sheets, navigation and
                // in-progress flows survive a trip to the background.
                // Hidden from assistive tech while covered.
                mainContent
                    .accessibilityHidden(privacyCover != nil)
            }
        }
        .environment(localization)
        .environment(\.locale, localization.effectiveLocale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .id(localization.selectedCode ?? "system")
        .onChange(of: localization.selectedCode) { _, _ in
            // The long-press menu is set at runtime to follow the in-app
            // language; without this it kept the old one until relaunch.
            QuickActionRouter.installHomeScreenShortcuts()
        }
        .onChange(of: dataStore.profile.biometricLockEnabled) { _, enabled in
            if !enabled { isUnlocked = true }
        }
        .onChange(of: dataStore.isAwaitingCloudAccountDecision) { _, awaiting in
            if !awaiting && !dataStore.profile.biometricLockEnabled { isUnlocked = true }
        }
        .onChange(of: privacyCover, initial: true) { _, cover in
            syncPrivacyCover(cover)
        }
        .onChange(of: isUnlocked) { _, unlocked in
            // The launch prompts wait for the lock to clear, and the Face
            // ID answer can land after the scene is already active again.
            guard unlocked, scenePhase == .active else { return }
            detectTimezoneChange()
            maybePresentWhatsNewTour()
            maybePresentWinBack()
        }
        // A116: after an iCloud sign-out or account switch the store
        // stays closed until the user says what happens to the data the
        // previous account left on this device.
        .alert(
            "iCloud account changed",
            isPresented: Binding(
                get: { dataStore.isAwaitingCloudAccountDecision },
                set: { _ in }
            )
        ) {
            Button("Keep on This iPhone") {
                dataStore.resolveCloudAccountChange(removingLocalData: false)
            }
            Button("Remove from This iPhone", role: .destructive) {
                dataStore.resolveCloudAccountChange(removingLocalData: true)
            }
        } message: {
            Text("Atlas data from the previous iCloud account is still on this iPhone. If you keep it, it syncs to the iCloud account you're signed in to now. Removing it doesn't touch the copy in the previous account's iCloud.")
        }
        .alert("App lock turned off", isPresented: $showLockReleasedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This iPhone no longer has a passcode, so Atlas can't stay locked. Set a passcode in Settings, then turn the lock back on in Profile.")
        }
        .onChange(of: dataStore.isAwaitingCloudAccountDecision, initial: true) { _, awaiting in
            // An open sheet would keep the prompt from presenting; the
            // screens behind these are empty during the hold anyway.
            guard awaiting else { return }
            dismissRootPresentations()
        }
        .task {
            // `.id` above gives this tree a new identity on every
            // language switch, which reruns its tasks and would cancel
            // any still in flight. Launch work runs once per process,
            // in unstructured tasks the view's lifetime can't cancel.
            guard !hasStartedLaunchWork else { return }
            hasStartedLaunchWork = true
            startLaunchWork()
        }
        .onOpenURL { url in
            // All `peptidex://` routing lives in DeepLinkRouter so
            // the widget / Live Activity / notification link
            // vocabulary is one tested mapping instead of an
            // inline switch per entry point.
            Task { @MainActor in
                let isPro = await StoreService.shared.resolvedProStatus()
                DeepLinkRouter.route(url, appState: appState, isPro: isPro)
            }
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
            appState.dismissModalsForRouting()
            appState.selectedTab = .meals
            appState.pendingFoodLogID = deepLink
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            // Midnight, a timezone change or a DST jump while the app
            // stays open: Today would otherwise keep yesterday's doses
            // until the next activation.
            guard scenePhase == .active else { return }
            dataStore.handleAppActivation()
            dataStore.reconcileDoseLiveActivities()
            detectTimezoneChange()
        }
        .sheet(item: $travelChange) { change in
            TravelModePromptSheet(
                change: change,
                exampleShift: travelExampleShift(for: change),
                onShift: {
                    dataStore.applyTravelShift(
                        toTimezone: change.currentIdentifier,
                        minutesDelta: change.minutesDelta
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
                pages: WhatsNewPage.current,
                onComplete: {
                    WhatsNewService.shared.markCurrentTourSeen()
                    showWhatsNewTour = false
                }
            )
            .interactiveDismissDisabled()
        }
    }

    private func startLaunchWork() {
        // Once per launch the user sees, not per `.active`: returning
        // from Control Center or a Face ID sheet isn't a launch, and
        // counting those cleared the review prompt's engagement gate
        // in the first session.
        ReviewPromptService.shared.recordLaunch()
        Task { @MainActor in
            // Decode the bundled peptide catalog off the main
            // thread, after the first frame. Every consumer
            // (Library, protocol builder, AI research) reads it
            // synchronously, so warming it here means none of them
            // is the one that pays — and launch doesn't either.
            await PeptideDatabase.warmUp()
        }
        // One-shot Spotlight reindex on app start. Custom foods
        // and favorites stay in sync via DataStore mutation
        // hooks, but a fresh install or a CloudKit pull on a
        // second device needs this to seed the index — without
        // it, the user wouldn't see their library in Spotlight
        // until they next edited a food.
        dataStore.reindexFoodSpotlight()
        // Subscribe to MetricKit so crash + hang + disk-write
        // payloads delivered the day after a problem occurs
        // are captured locally and, unless the user opted out,
        // sent as crash reports (`CrashReportUploader`).
        // Idempotent — subscribing on every launch is the
        // documented usage.
        DiagnosticsService.shared.startCollecting()
        Task(priority: .background) { @MainActor in
            // Register the App Attest key now, so the first research
            // question or meal scan doesn't wait on it.
            await AppAttestService.shared.warmUp()
        }
    }

    /// What `PrivacyLockWindow` should show. A plain cover whenever the
    /// scene isn't active, so the app-switcher snapshot (taken on the way
    /// to the background) never shows doses, weight or Biological Age.
    /// The lock screen once the app is coming back, so its Face ID prompt
    /// runs in the foreground — and stays through that prompt, which
    /// itself makes the scene inactive.
    private var privacyCover: PrivacyLockWindow.Cover? {
        guard hasCompletedOnboarding, dataStore.profile.biometricLockEnabled else { return nil }
        if !isUnlocked { return scenePhase == .background ? .snapshot : .lock }
        return scenePhase == .active ? nil : .snapshot
    }

    /// Closes every sheet and cover presented from the app root, and with
    /// them anything stacked on top.
    private func dismissRootPresentations() {
        appState.showProfile = false
        appState.showLibrary = false
        appState.presentedQuickSheet = nil
        appState.presentedPaywall = nil
        travelChange = nil
        showWhatsNewTour = false
    }

    private func syncPrivacyCover(_ cover: PrivacyLockWindow.Cover?) {
        switch cover {
        case .lock:
            PrivacyLockWindow.shared.show(.lock, content: privacyCoverContent(LockScreenView(
                onUnlock: { isUnlocked = true },
                onUnavailable: { releaseUnsatisfiableLock() }
            )))
        case .snapshot:
            PrivacyLockWindow.shared.show(.snapshot, content: privacyCoverContent(PrivacyCoverView()))
        case nil:
            PrivacyLockWindow.shared.hide()
        }
    }

    /// With the device passcode removed no owner authentication can pass,
    /// so the lock would hold the user's data out of reach for good. It
    /// turns itself off instead and says why (B091).
    private func releaseUnsatisfiableLock() {
        dataStore.profile.biometricLockEnabled = false
        dataStore.persistProfile()
        isUnlocked = true
        showLockReleasedNotice = true
    }

    /// The lock window hosts its own view tree, outside the app's
    /// environment, so it gets the language and theme here.
    private func privacyCoverContent(_ cover: some View) -> some View {
        cover
            .environment(\.locale, localization.effectiveLocale)
            .environment(\.layoutDirection, localization.layoutDirection)
            .preferredColorScheme(themeManager.displayMode.preferredScheme)
            .tint(AppColor.accentPrimary)
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
            // Checked after the delay, when the sheet would present: a
            // sheet already up (a tab's own, Profile, the travel prompt)
            // makes SwiftUI refuse this one while the flag stays set,
            // which would block every retry. Left unset, the next
            // `.active` tries again.
            guard canPresentRootModal else { return }
            showWhatsNewTour = true
        }
    }

    /// The single re-offer of the trial to a user who declined it in
    /// onboarding — see `UpsellScheduler` for the rules. Waits for
    /// StoreKit so trial eligibility is real rather than the pessimistic
    /// default, then yields to any launch-time prompt: it presents only
    /// when nothing else is on screen, and is marked shown the moment it
    /// presents so it can never come back.
    private func maybePresentWinBack() {
        guard hasCompletedOnboarding else { return }
        Task { @MainActor in
            let store = StoreService.shared
            if store.products.isEmpty { await store.loadProducts() }
            try? await Task.sleep(for: .seconds(1))
            let isPro = await store.resolvedProStatus()
            let isTrialEligible = store.isEligibleForMonthlyTrial || store.isEligibleForAnnualTrial
            guard UpsellScheduler.isWinBackDue(isPro: isPro, isTrialEligible: isTrialEligible),
                  canPresentRootModal
            else { return }
            UpsellScheduler.markWinBackShown()
            appState.presentedPaywall = .winBack
        }
    }

    /// True when the main UI is on screen with nothing presented over it —
    /// no lock screen, no launch prompt, no workout in progress, and no
    /// sheet or cover from any tab (read from UIKit, which sees
    /// presentations SwiftUI state here cannot).
    private var canPresentRootModal: Bool {
        guard !dataStore.profile.biometricLockEnabled || isUnlocked,
              !showWhatsNewTour,
              travelChange == nil,
              appState.presentedPaywall == nil,
              WorkoutSessionService.shared.activeSession == nil
        else { return false }
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return keyWindow?.rootViewController?.presentedViewController == nil
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
        // Not over onboarding: the prompt is about protocols the user
        // hasn't set up yet. Nor over another presentation, which would
        // refuse it and leave `travelChange` set, blocking the prompt
        // and the win-back for the session. The stored zone is only
        // updated once the user answers, so the next `.active` detects
        // the same change again.
        guard hasCompletedOnboarding,
              canPresentRootModal,
              let change = TimezoneChangeDetector.detect(previousIdentifier: stored)
        else { return }
        travelChange = change
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
        let shifted = TravelModeLogic.shiftTime(firstTime, byMinutes: change.minutesDelta)
        return (firstTime, shifted)
    }

    /// Ticks only for a tab the user picked. Routers, deep links and
    /// Spotlight set `selectedTab` directly, so they never buzz — often at
    /// launch, for a change the user didn't make.
    private var userTabSelection: Binding<AppTab> {
        Binding(
            get: { appState.selectedTab },
            set: { tab in
                if tab != appState.selectedTab { Haptics.selection() }
                appState.selectedTab = tab
            }
        )
    }

    private var coreTabView: some View {
        TabView(selection: userTabSelection) {
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
        // A tab bar on iPhone; on iPad, a top tab bar that expands into a
        // sidebar, so the wide screen isn't framed by a phone-style bar.
        .tabViewStyle(.sidebarAdaptable)
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
                .appAnimation(AppAnimation.toast,
                               value: dataStore.lastError)
        }
        #if DEBUG
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Floating "you're in screenshot mode" reminder sits
            // above the tab bar while ScreenshotMode is on. Debug-only,
            // like the Settings row that turns the mode on.
            ScreenshotModeBanner()
                .appAnimation(AppAnimation.toast,
                               value: ScreenshotMode.shared.isEnabled)
        }
        #endif
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
        // Home-screen shortcuts, Control Center controls and widget
        // buttons all land here, whichever tab is showing.
        .onChange(of: quickActionInbox.pending, initial: true) { _, action in
            guard let action else { return }
            quickActionInbox.pending = nil
            QuickActionRouter.perform(action, appState: appState, dataStore: dataStore)
        }
        .onChange(of: appState.pendingQuickAction, initial: true) { _, action in
            guard let action else { return }
            appState.pendingQuickAction = nil
            QuickActionRouter.perform(action, appState: appState, dataStore: dataStore)
        }
        .sheet(item: Bindable(appState).presentedQuickSheet) { sheet in
            switch sheet {
            case .scanMeal:
                MealScanFlow(onClose: { appState.presentedQuickSheet = nil })
                    .environment(dataStore)
                    .liquidGlassPresentation()
            case .logWeight:
                LogWeightSheet()
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
        }
        // App-wide paywall: `atlas://pro`, the one-time trial win-back,
        // and Today's research-assistant row for free users.
        .sheet(item: Bindable(appState).presentedPaywall) { source in
            PaywallView(source: source)
                .environment(dataStore)
                .liquidGlassPresentation()
        }
        .task {
            // Once per process, not per `.id` rebuild on a language
            // switch — and unstructured, so that rebuild can't cancel
            // a reconcile or permission request already under way.
            guard !hasStartedNotificationSync else { return }
            hasStartedNotificationSync = true
            Task { @MainActor in await syncNotifications() }
        }
    }

    private func syncNotifications() async {
        QuickActionRouter.installHomeScreenShortcuts()

        // Repopulate the in-memory ID tracker from iOS's actual pending
        // requests. Without this, force-quit leaves orphan reminders that
        // scheduleNotifications can't see in its set-diff and won't remove.
        await NotificationService.shared.reconcilePendingState()

        // Habit reminders are gated per-habit (Habit.reminderTime), not
        // by `doseRemindersEnabled`. Re-planned once the tracker above
        // knows what is pending; every activation re-plans them too.
        await dataStore.rescheduleHabitReminders()
        await DailyReminderScheduler.reconcile(dataStore: dataStore)

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

/// A UIKit background task that is ended exactly once: when the work
/// finishes, or when iOS's budget runs out first. An unended task at
/// expiry gets the app terminated rather than suspended.
@MainActor
private final class BackgroundTaskHandle {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// The strip above the tab bar. It answers "is today done?" for whatever
/// the user is currently looking at — workouts on Train, doses everywhere
/// else — because a dose reminder under the muscle map is answering a
/// question nobody on that screen asked. Without an active protocol there
/// are no doses to report, so the workout strip stands in: an empty
/// accessory would still draw its glass capsule, and "All doses completed"
/// with a syringe is noise for someone who never tracks one.
struct TabAccessoryView: View {
    let tab: AppTab
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        if tab == .train || dataStore.activeProtocols.isEmpty {
            // Train draws its own resume banner for a workout in
            // progress; repeating it here stacks two identical pills.
            WorkoutAccessoryView(reportsActiveWorkout: tab != .train)
        } else {
            NextDoseAccessoryView()
        }
    }
}

/// Train's counterpart to `NextDoseAccessoryView`. The session count is
/// held in state rather than read in `body`: `workoutSummary` faults
/// SwiftData, and the accessory re-renders on every tab change.
struct WorkoutAccessoryView: View {
    let reportsActiveWorkout: Bool
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
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .appAnimation(AppAnimation.springSnappy, value: loggedToday)
        .accessibilityElement(children: .combine)
        .task(id: dataStore.revision) {
            loggedToday = dataStore.workoutSummary().count
        }
    }

    private var showsActiveWorkout: Bool {
        reportsActiveWorkout && sessionService.activeSession != nil
    }

    private var icon: String {
        if showsActiveWorkout { return "figure.run" }
        return loggedToday > 0 ? "checkmark.circle.fill" : "dumbbell.fill"
    }

    private var label: LocalizedStringKey {
        if showsActiveWorkout { return "Workout in progress" }
        return loggedToday > 0
            ? "Workout logged today"
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
                Text(next.dose.isEmpty
                     ? "Next: \(next.peptide.abbreviation)"
                     : "Next: \(next.peptide.abbreviation) \u{2022} \(next.dose)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(next.date.formatted(.dateTime.hour().minute()))
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.accentLight)
                    .contentTransition(.numericText())
            } else {
                Text("All doses completed for today")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .appAnimation(AppAnimation.springSnappy, value: allDone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// One VoiceOver stop with the full name, instead of the icon,
    /// the abbreviated line with its bullet glyph, and the time.
    private var accessibilityLabel: Text {
        guard let next = dataStore.nextDose else { return Text("All doses completed for today") }
        let time = next.date.formatted(.dateTime.hour().minute())
        return next.dose.isEmpty
            ? Text("Next dose: \(next.peptide.name) at \(time)")
            : Text("Next dose: \(next.peptide.name), \(next.dose) at \(time)")
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
                    .foregroundStyle(AppColor.warning)
                Text(message)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(AppColor.warning.opacity(0.14))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: \(message)")
        }
    }
}
