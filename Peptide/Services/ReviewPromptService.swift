import StoreKit
import SwiftUI

/// Decides *when* to ask iOS to show the App Store review sheet.
///
/// The App Store guidelines forbid a custom 5-star UI — the only legal in-app
/// prompt is `SKStoreReviewController` (here surfaced via SwiftUI's
/// `RequestReviewAction`). iOS owns the actual sheet, throttles to ~3 prompts
/// per 365 days per app, and the user taps stars in one gesture.
///
/// The art is choosing the moment. We ask only after a positive milestone, on
/// an engaged user, and never more than once per app version or per 90 days.
@MainActor @Observable
final class ReviewPromptService {
    static let shared = ReviewPromptService()

    private let defaults = UserDefaults.standard
    private let installDateKey = "review.installDate"
    private let lastPromptDateKey = "review.lastPromptDate"
    private let lastPromptVersionKey = "review.lastPromptVersion"
    private let launchCountKey = "review.launchCount"

    private let minDaysSinceInstall = 3
    private let minLaunches = 4
    private let minDaysBetweenPrompts = 90

    private init() {
        if defaults.object(forKey: installDateKey) == nil {
            defaults.set(Date(), forKey: installDateKey)
        }
    }

    func recordLaunch() {
        let count = defaults.integer(forKey: launchCountKey) + 1
        defaults.set(count, forKey: launchCountKey)
    }

    /// Asks iOS to show the review sheet only if the user is engaged, the app
    /// hasn't asked recently, and we haven't already asked on this version.
    func requestReviewIfEligible(using request: RequestReviewAction) {
        guard isEligible else { return }
        fire(request)
    }

    /// Used when the user explicitly taps a "Rate the app" CTA (e.g. the
    /// onboarding review screen). Skips engagement gates — the user just
    /// opted in — but still honours the 90-day / per-version cooldown so the
    /// system sheet doesn't burn one of iOS's three annual prompts.
    func requestReviewOnUserAction(using request: RequestReviewAction) {
        guard isWithinCooldownWindow else { return }
        fire(request)
    }

    /// Internal (not private) so tests can validate the gating rules without
    /// having to construct a SwiftUI `RequestReviewAction`.
    var isEligible: Bool {
        let installDate = (defaults.object(forKey: installDateKey) as? Date) ?? Date()
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        guard daysSinceInstall >= minDaysSinceInstall else { return false }

        guard defaults.integer(forKey: launchCountKey) >= minLaunches else { return false }

        return isWithinCooldownWindow
    }

    /// True when no prompt has been shown on the current app version and the
    /// 90-day window since the last prompt has elapsed.
    var isWithinCooldownWindow: Bool {
        if let lastVersion = defaults.string(forKey: lastPromptVersionKey),
           lastVersion == currentVersion {
            return false
        }

        if let lastPrompt = defaults.object(forKey: lastPromptDateKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0
            guard daysSince >= minDaysBetweenPrompts else { return false }
        }

        return true
    }

    private func fire(_ request: RequestReviewAction) {
        request()
        defaults.set(Date(), forKey: lastPromptDateKey)
        defaults.set(currentVersion, forKey: lastPromptVersionKey)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
