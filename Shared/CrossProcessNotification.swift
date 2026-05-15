import Foundation

/// Cross-process notification names used to wake the main app
/// when the widget extension queues work the app should pick up.
///
/// Darwin notifications (`CFNotificationCenter`) are the only
/// notification mechanism that crosses iOS process boundaries.
/// `NotificationCenter.default` is intra-process; `UserDefaults`
/// KVO across an App Group is unreliable.
enum CrossProcessNotification {
    /// Posted by the widget-extension live-activity intent every
    /// time it queues a "log this dose" marker. The main app's
    /// observer drains the inbox + reconciles activities the
    /// instant the notification arrives, so a tap-and-immediately-
    /// switch-back lands in the app with the dose already
    /// flipped.
    static let pendingDoseLogQueued = "com.peptidesai.app.pendingDoseLogQueued"
}
