import Foundation
@preconcurrency import UserNotifications

/// Turns `DailyReminderEngine`'s plan into pending notification requests.
///
/// Reconciled whenever the app becomes active or goes to the background,
/// and after anything the reminders depend on changes, so a meal logged
/// before its reminder silently cancels that day's nudge.
@MainActor
enum DailyReminderScheduler {
    nonisolated static let mealCategoryID = "MEAL_REMINDER"
    nonisolated static let mealRepeatCategoryID = "MEAL_REMINDER_REPEAT"
    nonisolated static let workoutCategoryID = "WORKOUT_REMINDER"
    nonisolated static let weighInCategoryID = "WEIGH_IN_REMINDER"

    nonisolated static let scanMealAction = "SCAN_MEAL"
    nonisolated static let repeatMealAction = "REPEAT_MEAL"
    nonisolated static let startWorkoutAction = "START_WORKOUT"
    nonisolated static let logWeightAction = "LOG_WEIGHT"

    static func reconcile(dataStore: DataStore) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(NotificationService.dailyIDPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let settings = DailyReminderSettings.load(training: dataStore.profile.trainingPreferences)
        guard settings.hasAnyEnabled, await isAuthorised else {
            NotificationService.shared.trackDailyReminders([])
            return
        }

        let profile = dataStore.profile
        let calendar = Calendar.current
        let trainingWeekdays = Set((profile.trainingPreferences?.preferredDays ?? []).map(\.calendarWeekdayValue))
        let today = calendar.startOfDay(for: Date())
        let trainedDays = (0..<DailyReminderEngine.lookaheadDays)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter { dataStore.workoutSummary(for: $0).count > 0 }
        let planned = DailyReminderEngine.plan(
            settings: settings,
            trainingWeekdays: trainingWeekdays,
            now: Date(),
            calendar: calendar
        ) { kind, day in
            switch kind {
            case .weighIn:
                profile.weightHistory.contains { calendar.isDate($0.date, inSameDayAs: day) }
            case .workout:
                trainedDays.contains { calendar.isDate($0, inSameDayAs: day) }
            case .breakfast, .lunch, .dinner:
                profile.mealHistory.contains {
                    $0.category == kind.mealCategory && calendar.isDate($0.date, inSameDayAs: day)
                }
            }
        }

        for reminder in planned {
            let content = content(for: reminder, mealHistory: profile.mealHistory, calendar: calendar)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                AppLog.notifications.error("Daily reminder add failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        NotificationService.shared.trackDailyReminders(Set(planned.map(\.id)))
    }

    static var categories: Set<UNNotificationCategory> {
        let scan = UNNotificationAction(
            identifier: scanMealAction,
            title: String(localized: "Scan meal", comment: "Meal reminder action — opens the Meals tab"),
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "camera.viewfinder")
        )
        let repeatMeal = UNNotificationAction(
            identifier: repeatMealAction,
            title: String(localized: "Same as yesterday", comment: "Meal reminder action — re-logs yesterday's meal"),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.backward")
        )
        let startWorkout = UNNotificationAction(
            identifier: startWorkoutAction,
            title: String(localized: "Start workout", comment: "Workout reminder action"),
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "play.fill")
        )
        let logWeight = UNTextInputNotificationAction(
            identifier: logWeightAction,
            title: String(localized: "Log weight", comment: "Weigh-in reminder action"),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "scalemass.fill"),
            textInputButtonTitle: String(localized: "Save"),
            textInputPlaceholder: String(localized: "Today's weight", comment: "Weigh-in reply field placeholder")
        )
        return [
            UNNotificationCategory(identifier: mealCategoryID, actions: [scan], intentIdentifiers: []),
            UNNotificationCategory(identifier: mealRepeatCategoryID, actions: [repeatMeal, scan], intentIdentifiers: []),
            UNNotificationCategory(identifier: workoutCategoryID, actions: [startWorkout], intentIdentifiers: []),
            UNNotificationCategory(identifier: weighInCategoryID, actions: [logWeight], intentIdentifiers: []),
        ]
    }

    // MARK: - Content

    private static func content(
        for reminder: DailyReminderEngine.Planned,
        mealHistory: [MealEntry],
        calendar: Calendar
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = NotificationService.dailyIDPrefix + reminder.kind.rawValue
        content.title = reminder.kind.displayName

        switch reminder.kind {
        case .weighIn:
            content.body = String(localized: "Step on the scale, then reply with today's number.")
            content.categoryIdentifier = weighInCategoryID
            content.userInfo = ["deeplink": "peptidex://today"]
        case .workout:
            content.title = String(localized: "Training day")
            content.body = String(localized: "Your session is on the plan — tap to get started.")
            content.categoryIdentifier = workoutCategoryID
            content.userInfo = ["deeplink": "peptidex://train"]
        case .breakfast, .lunch, .dinner:
            guard let category = reminder.kind.mealCategory else { break }
            content.userInfo = ["deeplink": "peptidex://meals", "mealCategory": category.rawValue]
            let previous = DailyReminderEngine.previousDayMeals(category, before: reminder.fireDate, in: mealHistory, calendar: calendar)
            if previous.isEmpty {
                content.body = String(localized: "Snap your plate — logging takes a few seconds.")
                content.categoryIdentifier = mealCategoryID
            } else {
                // Baked in at schedule time; the plan is rebuilt on every
                // foreground and background, so it tracks yesterday's log.
                let names = previous.map(\.name).joined(separator: ", ")
                let calories = previous.reduce(0) { $0 + $1.calories }
                content.body = String(localized: "Same as yesterday? \(names) · \(calories) kcal")
                content.categoryIdentifier = mealRepeatCategoryID
            }
        }
        return content
    }

    private static var isAuthorised: Bool {
        get async {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .ephemeral, .provisional: true
            default: false
            }
        }
    }
}
