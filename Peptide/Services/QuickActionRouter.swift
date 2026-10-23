import SwiftUI
import UIKit

/// Performs a `QuickAction` inside the running app, whichever surface it
/// came from: a home-screen shortcut, a Control Center control, a widget
/// link or a `peptidex://quick/…` URL.
@MainActor
enum QuickActionRouter {
    static func perform(_ action: QuickAction, appState: AppState, dataStore: DataStore) {
        // Sheets present from the root and can't stack on an open modal.
        appState.showProfile = false
        appState.showLibrary = false

        switch action {
        case .scanMeal:
            appState.presentedQuickSheet = .scanMeal
        case .logWeight:
            appState.presentedQuickSheet = .logWeight
        case .logWater:
            logGlass(at: Date(), into: dataStore)
            Haptics.success()
            appState.selectedTab = .today
        case .startWorkout:
            appState.selectedTab = .train
            if WorkoutSessionService.shared.activeSession == nil {
                WorkoutSessionService.shared.startWorkout()
            }
        }
    }

    /// Long-press menu on the app icon. Set at runtime rather than in
    /// Info.plist so the titles follow the in-app language.
    static func installHomeScreenShortcuts() {
        UIApplication.shared.shortcutItems = QuickAction.allCases.map { action in
            UIApplicationShortcutItem(
                type: action.rawValue,
                localizedTitle: String(localized: action.title),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: action.systemImage)
            )
        }
    }

    // MARK: - Water taps from outside the app

    /// Applies every glass tapped in Control Center or on a widget since
    /// the last drain, stamped with the time of the tap.
    static func drainPendingWater(into dataStore: DataStore) {
        let taps = PendingWaterLogStore.drain()
        guard !taps.isEmpty else { return }
        for tappedAt in taps {
            logGlass(at: tappedAt, into: dataStore)
        }
        dataStore.flushPendingSave()
    }

    /// Drains the water inbox the moment a tap is queued while the app
    /// process is alive. Caller retains the token for the process lifetime.
    static func observePendingWater() -> PendingDoseLogProcessor.ObservationToken {
        let token = PendingDoseLogProcessor.ObservationToken()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(token).toOpaque(),
            { _, _, _, _, _ in
                Task { @MainActor in
                    QuickActionRouter.drainPendingWater(into: IntentDataStore.resolve())
                }
            },
            CrossProcessNotification.pendingWaterLogQueued as CFString,
            nil,
            .deliverImmediately
        )
        return token
    }

    private static func logGlass(at date: Date, into dataStore: DataStore) {
        let glass = TodayChecklistEngine.glassFluidOunces(for: dataStore.profile.bodyMetrics.unit)
        dataStore.logWater(fluidOunces: glass, date: date)
    }
}

/// Root-presented sheets a quick action can open.
enum QuickActionSheet: String, Identifiable {
    case scanMeal, logWeight
    var id: String { rawValue }
}

// MARK: - Home-screen shortcut plumbing

/// SwiftUI has no hook for home-screen quick actions, so a minimal app
/// delegate installs a scene delegate that forwards them to
/// `QuickActionInbox`, which `PeptideApp` watches. It also listens for
/// the Live Activity, widget and Control Center buttons.
final class AtlasAppDelegate: NSObject, UIApplicationDelegate {
    private var workoutActionToken: PendingDoseLogProcessor.ObservationToken?
    private var doseLogToken: PendingDoseLogProcessor.ObservationToken?
    private var waterToken: PendingDoseLogProcessor.ObservationToken?

    /// Registered here rather than in a view because iOS may launch the
    /// app in the background just to run a Live Activity, widget or
    /// control intent, and no scene builds on that launch.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            PendingWorkoutActionStore.applyInProcess = { WorkoutActivityActionProcessor.drain() }
            workoutActionToken = WorkoutActivityActionProcessor.startObserving()
            doseLogToken = PendingDoseLogProcessor.startObserving()
            waterToken = QuickActionRouter.observePendingWater()
            WorkoutActivityActionProcessor.drain()
            let store = IntentDataStore.resolve()
            PendingDoseLogProcessor.drain(into: store)
            QuickActionRouter.drainPendingWater(into: store)
            store.reconcileDoseLiveActivities()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Cold launch from a shortcut arrives here, not in the scene delegate.
        if let item = options.shortcutItem {
            MainActor.assumeIsolated { QuickActionInbox.shared.pending = QuickAction(rawValue: item.type) }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = AtlasSceneDelegate.self
        return configuration
    }
}

final class AtlasSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let action = QuickAction(rawValue: shortcutItem.type)
        MainActor.assumeIsolated { QuickActionInbox.shared.pending = action }
        completionHandler(action != nil)
    }
}
