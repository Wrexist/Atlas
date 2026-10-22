import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let dataStore: DataStore
    let appState: AppState

    init(dataStore: DataStore, appState: AppState) {
        self.dataStore = dataStore
        self.appState = appState
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let action = response.actionIdentifier

        // Snooze handling: any of the three snooze action IDs
        // resolves to a duration through the service. Single
        // reschedule path keeps the durations + identifiers in
        // sync — adding a fourth duration only requires a new
        // case in the service's switch, not a delegate change.
        if let snoozeSeconds = NotificationService.snoozeDuration(forActionIdentifier: action) {
            guard let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent else {
                completionHandler()
                return
            }
            let snoozeID = "\(NotificationService.snoozeIDPrefix)\(UUID().uuidString)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snoozeSeconds, repeats: false)
            let request = UNNotificationRequest(identifier: snoozeID, content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    AppLog.notifications.error("Snooze reschedule failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            Task { @MainActor in
                NotificationService.shared.registerPendingSnooze(id: snoozeID)
            }
            completionHandler()
            return
        }

        switch action {
        case "MARK_TAKEN":
            let userInfo = response.notification.request.content.userInfo
            let protocolIdStr = userInfo["protocolId"] as? String
            let scheduledHour = userInfo["hour"] as? Int
            let scheduledMinute = userInfo["minute"] as? Int

            Task { @MainActor [dataStore] in
                defer { completionHandler() }

                guard let protocolIdStr,
                      let protocolId = UUID(uuidString: protocolIdStr),
                      let hour = scheduledHour,
                      let minute = scheduledMinute else { return }

                let due = Self.entriesDue(
                    in: dataStore.entries,
                    protocolId: protocolId,
                    hour: hour,
                    minute: minute
                )
                for entry in due {
                    dataStore.markEntryComplete(entry.id)
                }
                dataStore.flushPendingSave()
            }
            return

        case DailyReminderScheduler.repeatMealAction:
            let userInfo = response.notification.request.content.userInfo
            let categoryRaw = userInfo["mealCategory"] as? String
            let firedAt = response.notification.date
            Task { @MainActor [dataStore] in
                defer { completionHandler() }
                guard let categoryRaw, let category = MealCategory(rawValue: categoryRaw) else { return }
                dataStore.repeatMeals(category, from: firedAt)
                // A background action: iOS may suspend the moment the
                // completion handler runs, before the debounced save lands.
                dataStore.flushPendingSave()
                await DailyReminderScheduler.reconcile(dataStore: dataStore)
            }
            return

        case DailyReminderScheduler.logWeightAction:
            let typed = (response as? UNTextInputNotificationResponse)?.userText ?? ""
            Task { @MainActor [dataStore] in
                defer { completionHandler() }
                guard let kilograms = DailyReminderEngine.parsedWeightKilograms(
                    typed,
                    unit: dataStore.profile.bodyMetrics.unit
                ) else {
                    AppLog.notifications.warning("Weigh-in reply was not a usable weight")
                    return
                }
                dataStore.logWeight(kg: kilograms)
                dataStore.flushPendingSave()
                await DailyReminderScheduler.reconcile(dataStore: dataStore)
            }
            return

        default:
            break
        }

        // Deep-link routing for a plain tap on the notification body, and
        // for the foreground actions that only need to land somewhere.
        // Local-notification taps never pass through `onOpenURL`, so mirror
        // it: hand the embedded `deeplink` to the same router the widgets
        // and Live Activities use.
        let opensDeepLink = [
            UNNotificationDefaultActionIdentifier,
            DailyReminderScheduler.scanMealAction,
            DailyReminderScheduler.startWorkoutAction,
        ].contains(action)
        if opensDeepLink,
           let deeplink = response.notification.request.content.userInfo["deeplink"] as? String,
           let url = URL(string: deeplink) {
            Task { @MainActor [appState] in
                defer { completionHandler() }
                DeepLinkRouter.route(url, appState: appState, isPro: await StoreService.shared.resolvedProStatus())
            }
            return
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let isRestEnd = notification.request.identifier.hasPrefix(
            NotificationService.adHocIDPrefix + WorkoutSessionService.restNotificationPrefix
        )
        Task { @MainActor [appState] in
            // The workout screen marks rest end with a haptic and an
            // announcement; a banner over it on top of that is noise.
            let workoutOnScreen = isRestEnd && appState.selectedTab == .train
            completionHandler(workoutOnScreen ? [] : [.banner, .sound])
        }
    }

    /// Every incomplete dose a combined reminder covers: the newest day in
    /// the last 24 hours with an already-due entry at `hour:minute` for
    /// `protocolId`, and all of that day's entries in the slot. The 24-hour window lets
    /// a snooze that fires after midnight still reach yesterday's doses;
    /// keeping to one day stops it from also marking an older dose at the
    /// same time the user never took.
    static func entriesDue(
        in entries: [ProtocolEntry],
        protocolId: UUID,
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProtocolEntry] {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let inSlot = entries.filter { entry in
            guard entry.protocolId == protocolId,
                  !entry.completed,
                  entry.date >= cutoff,
                  entry.date <= now else { return false }
            return calendar.component(.hour, from: entry.date) == hour
                && calendar.component(.minute, from: entry.date) == minute
        }
        guard let newest = inSlot.map(\.date).max() else { return [] }
        return inSlot.filter { calendar.isDate($0.date, inSameDayAs: newest) }
    }
}
