import Foundation
import Observation
import SwiftUI
import UserNotifications

/// The countdowns a recipe's steps have started. Shared by the recipe page
/// and cooking mode, so a timer started on one keeps running on the other,
/// and kept by `CookingTimerStore` past the page, so a timer started before
/// going back is still there, and still rings, when the recipe is reopened.
/// Each running timer also has a pending notification, so it is heard
/// with the phone locked. It never asks for permission: without it the
/// in-app countdown and haptic still work.
@MainActor
@Observable
final class CookingTimers {

    let recipeID: String
    /// Names the dish on the notification, which may ring with the page
    /// closed. Kept in the app's current language by the recipe page.
    var recipeName: String

    init(recipeID: String, recipeName: String) {
        self.recipeID = recipeID
        self.recipeName = recipeName
    }

    /// One timer: step `step`'s `index`-th timed wait.
    struct Key: Hashable, Sendable {
        let step: Int
        let index: Int
    }

    private(set) var endDates: [Key: Date] = [:]
    private(set) var finished: Set<Key> = []
    @ObservationIgnored private var tasks: [Key: Task<Void, Never>] = [:]

    func isRunning(_ key: Key) -> Bool { endDates[key] != nil }

    /// Nothing running and nothing rung, so there is nothing to come back to.
    var isIdle: Bool { endDates.isEmpty && finished.isEmpty }

    struct Running: Identifiable, Hashable {
        let key: Key
        let end: Date
        var id: Key { key }
    }

    /// Every running timer, soonest first.
    var running: [Running] {
        endDates.map { Running(key: $0.key, end: $0.value) }.sorted { $0.end < $1.end }
    }

    func start(_ key: Key, seconds: Int) {
        cancel(key)
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        endDates[key] = end
        tasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.ring(key)
        }
        let requestID = identifier(for: key)
        let body = String(localized: "\(recipeName) · Step \(key.step + 1)", comment: "Cooking timer notification body: the dish and the step whose timer ran out")
        Task { await Self.scheduleNotification(identifier: requestID, body: body, seconds: seconds) }
    }

    func cancel(_ key: Key) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: key)])
        tasks[key]?.cancel()
        tasks[key] = nil
        endDates[key] = nil
        finished.remove(key)
    }

    // MARK: - Notification

    nonisolated static let identifierPrefix = "cooktimer-"

    /// Carries the recipe, so the same step of another recipe never
    /// replaces this one's pending notification.
    func identifier(for key: Key) -> String {
        "\(Self.identifierPrefix)\(recipeID)-\(key.step)-\(key.index)"
    }

    private static func scheduleNotification(identifier: String, body: String, seconds: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .ephemeral, .provisional].contains(settings.authorizationStatus) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Cooking timer done", comment: "Notification title when a recipe step's timer runs out")
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        } catch {
            AppLog.notifications.error("Cooking timer add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ring(_ key: Key) {
        endDates[key] = nil
        tasks[key] = nil
        finished.insert(key)
        Haptics.success()
        // Haptics can be off and the notification is skipped without
        // permission, so VoiceOver gets its own cue.
        AccessibilityNotification.Announcement(String(localized: "Step \(key.step + 1) timer done")).post()
    }

    /// "4:05", or "1:02:30" past an hour.
    nonisolated static func clock(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// "8 min", "1 hr, 30 min" in the user's language.
    nonisolated static func label(seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}

/// One `CookingTimers` per recipe while its page is showing or one of its
/// timers is running or rung, so leaving a recipe page doesn't drop its
/// running timers and idle ones don't pile up over the session.
@MainActor
final class CookingTimerStore {
    static let shared = CookingTimerStore()

    private var timers: [String: CookingTimers] = [:]

    func timers(for recipeID: String, recipeName: String) -> CookingTimers {
        let entry = timers[recipeID] ?? CookingTimers(recipeID: recipeID, recipeName: recipeName)
        entry.recipeName = recipeName
        timers[recipeID] = entry
        return entry
    }

    /// Keeps a showing page's timers findable, naming the dish in the
    /// current language. An idle stand-in made while the page was hidden
    /// gives way to it.
    func keep(_ cookingTimers: CookingTimers, recipeName: String) {
        cookingTimers.recipeName = recipeName
        if let existing = timers[cookingTimers.recipeID], existing !== cookingTimers, !existing.isIdle { return }
        timers[cookingTimers.recipeID] = cookingTimers
    }

    /// Lets a page's timers go once it is off screen with nothing running
    /// or rung.
    func release(_ cookingTimers: CookingTimers) {
        guard timers[cookingTimers.recipeID] === cookingTimers, cookingTimers.isIdle else { return }
        timers[cookingTimers.recipeID] = nil
    }
}
