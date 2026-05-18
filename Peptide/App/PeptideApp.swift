import SwiftUI
import UserNotifications
import CoreSpotlight

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

        // App.init() may be nonisolated in strict Swift 6 mode; assumeIsolated
        // bridges to @MainActor safely since @main always runs on the main thread.
        _dataStore = State(wrappedValue: MainActor.assumeIsolated {
            MigrationService.shared.migrateIfNeeded()
            let store = DataStore()
            WatchSyncService.shared.onMarkComplete = { entryId, _ in
                store.toggleEntry(entryId)
            }
            WatchSyncService.shared.onMarkIncomplete = { entryId, _ in
                if store.entries.first(where: { $0.id == entryId })?.completed == true {
                    store.toggleEntry(entryId)
                }
            }
            WatchSyncService.shared.onLogWater = { oz in
                store.logWater(oz: oz)
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
            .task(id: dataStore.profile.healthConnected) {
                if dataStore.profile.healthConnected {
                    await HealthKitService.shared.startBackgroundDelivery()
                } else {
                    HealthKitService.shared.stopBackgroundDelivery()
                }
            }
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
                // unless the endpoint is configured AND the user
                // finished onboarding — partial in-flight runs stay
                // local until completion.
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
                // Live Activity tap → `peptidex://dose/<uuid>`. Park
                // the UUID on AppState; HomeView consumes it on its
                // next appear and presents the dose-logging sheet.
                // Unknown schemes / paths fall through silently so a
                // garbled custom-scheme tap from another app doesn't
                // log an error or open an unrelated view.
                guard url.scheme == "peptidex" else { return }
                switch url.host {
                case "dose":
                    // Live Activity tap → `peptidex://dose/<uuid>`.
                    guard let entryUUID = UUID(uuidString: url.lastPathComponent) else { return }
                    appState.selectedTab = .today
                    appState.pendingDoseLogEntryId = entryUUID
                case "weekly":
                    // Weekly recap notification → `peptidex://weekly/current`.
                    appState.selectedTab = .today
                    appState.pendingWeeklyRecap = true
                default:
                    return
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
            Tab("Train", systemImage: "figure.strengthtraining.traditional", value: .train) {
                TrainContainerView()
            }
            Tab("Meals", systemImage: "fork.knife", value: .meals) {
                MealsContainerView()
            }
            Tab("Biology", systemImage: "heart.fill", value: .biology) {
                BiologyView()
            }
            Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                PeptideListView()
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            if dataStore.profile.hapticFeedbackEnabled {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    @ViewBuilder
    private var tabViewWithAccessory: some View {
        if #available(iOS 26.0, *) {
            coreTabView.tabViewBottomAccessory { NextDoseAccessoryView() }
        } else {
            coreTabView
        }
    }

    private var mainContent: some View {
        tabViewWithAccessory
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
        .task {
            let delegate = NotificationDelegate(dataStore: dataStore)
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
