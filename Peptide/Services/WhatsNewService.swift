import Foundation

/// Single source of truth for "should I show the tour on this
/// launch?". The version-stamp approach lets us re-fire the tour
/// for *every* user (not just fresh installs) when a future
/// release bumps the constant — same pattern Notes / Reminders
/// use for their major-update splash screens.
///
/// Backed by UserDefaults under one key (no full schema migration
/// needed). Resets are explicit via `markPending(version:)` —
/// useful for tests and for the "preview tour" debug affordance
/// in a future settings screen.
@MainActor
final class WhatsNewService {
    static let shared = WhatsNewService()

    /// Bump this when the tour content changes meaningfully so the
    /// next launch presents the new tour to every user. The
    /// version is opaque to the storage layer; we just compare for
    /// equality, so any monotonic scheme works.
    static let currentTourVersion = "v2.0"

    private let storageKey = "com.peptidesai.app.whatsNew.lastSeenVersion"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stamps the current tour version as seen on a brand-new
    /// install — the user is about to walk through the regular
    /// onboarding flow which already covers the new feature
    /// surface, so re-firing this tour the moment they finish
    /// would be redundant. Idempotent: once a version is
    /// stamped, this is a no-op forever.
    ///
    /// Call from `PeptideApp` on every transition to `.active`
    /// before the should-show check. The early return when the
    /// stamp already exists keeps the launch path cheap.
    func bootstrapForFreshInstallIfNeeded(hasCompletedOnboarding: Bool) {
        guard defaults.string(forKey: storageKey) == nil,
              !hasCompletedOnboarding
        else { return }
        markCurrentTourSeen()
    }

    /// True when the user hasn't yet seen the tour for
    /// `currentTourVersion`. Suppresses the prompt on the very
    /// first launch (fresh install → the regular onboarding flow
    /// already covers the basics) by short-circuiting against the
    /// `hasCompletedOnboarding` flag the caller passes in.
    func shouldShowTour(hasCompletedOnboarding: Bool) -> Bool {
        guard hasCompletedOnboarding else { return false }
        let lastSeen = defaults.string(forKey: storageKey)
        return lastSeen != Self.currentTourVersion
    }

    /// Stamps `currentTourVersion` as seen. Call from the tour
    /// sheet's dismiss / completion paths so a re-launch in the
    /// same session doesn't re-fire the prompt.
    func markCurrentTourSeen() {
        defaults.set(Self.currentTourVersion, forKey: storageKey)
    }

    /// Test / debug hook: forget every version stamp so the next
    /// launch presents the current tour again.
    func resetForTesting() {
        defaults.removeObject(forKey: storageKey)
    }
}
