import SwiftUI
import UserNotifications

@main
struct PeptideApp: App {
    @State private var appState = AppState()
    @State private var dataStore: DataStore
    @State private var localization = LocalizationManager.shared
    @State private var themeManager = ThemeManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var notificationDelegate: NotificationDelegate?
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase

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
                // Re-evaluate which scheduled doses are in their
                // active window so the lock-screen Live Activities
                // start / end without needing the user to open the
                // app to a specific tab.
                DoseLiveActivityService.shared.reconcile(entries: dataStore.entries)
            }
        }
    }

    private var coreTabView: some View {
        TabView(selection: $appState.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeContainerView()
            }
            Tab("Peptides", systemImage: "flask.fill", value: .database) {
                PeptideListView()
            }
            Tab("Protocols", systemImage: "list.clipboard.fill", value: .protocols) {
                ProtocolListView()
            }
            Tab("Analytics", systemImage: "chart.bar.fill", value: .analytics) {
                AnalyticsView()
            }
            Tab("Profile", systemImage: "person.fill", value: .profile) {
                ProfileView()
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
        .environment(appState)
        .environment(dataStore)
        .preferredColorScheme(themeManager.displayMode.preferredScheme)
        .tint(AppColor.accentPrimary)
        .task {
            let delegate = NotificationDelegate(dataStore: dataStore)
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
            NotificationService.shared.registerCategories()

            // Repopulate the in-memory ID tracker from iOS's actual pending
            // requests. Without this, force-quit leaves orphan reminders that
            // scheduleNotifications can't see in its set-diff and won't remove.
            await NotificationService.shared.reconcilePendingState()

            guard dataStore.profile.doseRemindersEnabled else {
                NotificationService.shared.cancelAll()
                return
            }

            let status = await NotificationService.shared.checkAuthorization()
            if status == .notDetermined {
                let granted = await NotificationService.shared.requestAuthorization()
                if !granted {
                    dataStore.profile.doseRemindersEnabled = false
                    dataStore.persistProfile()
                    NotificationService.shared.cancelAll()
                    return
                }
            } else if status == .denied {
                dataStore.profile.doseRemindersEnabled = false
                dataStore.persistProfile()
                NotificationService.shared.cancelAll()
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
