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

    /// Drains the water inbox the moment a tap is queued while the app is
    /// running. Caller retains the token for the scene's lifetime.
    static func observePendingWater() -> PendingDoseLogProcessor.ObservationToken {
        let token = PendingDoseLogProcessor.ObservationToken()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(token).toOpaque(),
            { _, _, _, _, _ in
                Task { @MainActor in
                    guard let store = DataStore.current else { return }
                    QuickActionRouter.drainPendingWater(into: store)
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
/// `QuickActionInbox`, which `PeptideApp` watches.
final class AtlasAppDelegate: NSObject, UIApplicationDelegate {
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
