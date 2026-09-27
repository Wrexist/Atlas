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
    /// Marks the start of this app session — the singleton is first
    /// touched by `recordLaunch()` on the first `.active` transition.
    private let sessionStart = Date()

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
    /// Also skipped for the rest of a session in which a paywall was shown:
    /// asking for a rating right after an upsell reads as a pressure
    /// sequence, and the user's mood at that moment is not the milestone's.
    func requestReviewIfEligible(using request: RequestReviewAction) {
        guard isEligible, !paywallShownThisSession else { return }
        fire(request)
    }

    /// Finishing a workout is worth a prompt when it set a personal record
    /// or was the user's third — early enough to catch a new habit, late
    /// enough that the user knows what they are rating.
    static func isWorkoutReviewMoment(detectedPRCount: Int, completedWorkoutCount: Int) -> Bool {
        detectedPRCount > 0 || completedWorkoutCount == 3
    }

    /// `PaywallView` records `paywall_viewed_<source>` on every appearance;
    /// reading that log keeps this check out of the paywall itself.
    static func paywallViewed(
        in events: [OnboardingFunnelTracker.EventEntry],
        since start: Date
    ) -> Bool {
        events.contains { $0.timestamp >= start && $0.name.hasPrefix("paywall_viewed_") }
    }

    private var paywallShownThisSession: Bool {
        Self.paywallViewed(in: OnboardingFunnelTracker.snapshot.events, since: sessionStart)
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
