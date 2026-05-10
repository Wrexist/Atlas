import XCTest
@testable import Peptide

@MainActor
final class ReviewPromptServiceTests: XCTestCase {

    private var service: ReviewPromptService!
    private let defaults = UserDefaults.standard

    private static let installDateKey = "review.installDate"
    private static let lastPromptDateKey = "review.lastPromptDate"
    private static let lastPromptVersionKey = "review.lastPromptVersion"
    private static let launchCountKey = "review.launchCount"

    override func setUp() {
        super.setUp()
        // Each test starts from a known UserDefaults state. The service is a
        // singleton so we cannot recreate it; the eligibility check reads
        // defaults each time, so manipulating defaults is enough.
        // Inlined rather than calling a helper because helpers on a @MainActor
        // XCTestCase can't be called from the nonisolated setUp/tearDown
        // overrides without tripping Swift 6's data-race checker.
        defaults.removeObject(forKey: Self.installDateKey)
        defaults.removeObject(forKey: Self.lastPromptDateKey)
        defaults.removeObject(forKey: Self.lastPromptVersionKey)
        defaults.removeObject(forKey: Self.launchCountKey)
        service = ReviewPromptService.shared
    }

    override func tearDown() {
        defaults.removeObject(forKey: Self.installDateKey)
        defaults.removeObject(forKey: Self.lastPromptDateKey)
        defaults.removeObject(forKey: Self.lastPromptVersionKey)
        defaults.removeObject(forKey: Self.launchCountKey)
        service = nil
        super.tearDown()
    }

    // MARK: - recordLaunch

    func test_recordLaunch_incrementsCount() {
        XCTAssertEqual(defaults.integer(forKey: Self.launchCountKey), 0)
        service.recordLaunch()
        XCTAssertEqual(defaults.integer(forKey: Self.launchCountKey), 1)
        service.recordLaunch()
        XCTAssertEqual(defaults.integer(forKey: Self.launchCountKey), 2)
    }

    // MARK: - isEligible gating

    /// Fresh install with zero launches — never eligible.
    func test_isEligible_freshInstall_returnsFalse() {
        defaults.set(Date(), forKey: Self.installDateKey)
        XCTAssertFalse(service.isEligible)
    }

    /// Install older than 3 days but launch count < 4 — still ineligible.
    func test_isEligible_oldInstallButFewLaunches_returnsFalse() {
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86400)
        defaults.set(tenDaysAgo, forKey: Self.installDateKey)
        defaults.set(2, forKey: Self.launchCountKey)
        XCTAssertFalse(service.isEligible)
    }

    /// Install < 3 days ago, even with many launches — still ineligible.
    func test_isEligible_recentInstallManyLaunches_returnsFalse() {
        let oneDayAgo = Date().addingTimeInterval(-86400)
        defaults.set(oneDayAgo, forKey: Self.installDateKey)
        defaults.set(20, forKey: Self.launchCountKey)
        XCTAssertFalse(service.isEligible)
    }

    /// Engaged user, never prompted — eligible.
    func test_isEligible_engagedUserNeverPrompted_returnsTrue() {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        defaults.set(weekAgo, forKey: Self.installDateKey)
        defaults.set(10, forKey: Self.launchCountKey)
        XCTAssertTrue(service.isEligible)
    }

    /// Already prompted on the current version — ineligible regardless of date.
    func test_isEligible_promptedOnCurrentVersion_returnsFalse() {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        defaults.set(weekAgo, forKey: Self.installDateKey)
        defaults.set(10, forKey: Self.launchCountKey)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        defaults.set(currentVersion, forKey: Self.lastPromptVersionKey)
        XCTAssertFalse(service.isEligible)
    }

    /// Prompted < 90 days ago on a different version — ineligible.
    func test_isEligible_promptedRecentlyOnDifferentVersion_returnsFalse() {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        defaults.set(weekAgo, forKey: Self.installDateKey)
        defaults.set(10, forKey: Self.launchCountKey)
        defaults.set("0.0.0-old", forKey: Self.lastPromptVersionKey)
        defaults.set(Date().addingTimeInterval(-30 * 86400), forKey: Self.lastPromptDateKey)
        XCTAssertFalse(service.isEligible)
    }

    /// Prompted ≥ 90 days ago on a different version — eligible again.
    func test_isEligible_promptedLongAgoOnDifferentVersion_returnsTrue() {
        let yearAgo = Date().addingTimeInterval(-365 * 86400)
        defaults.set(yearAgo, forKey: Self.installDateKey)
        defaults.set(50, forKey: Self.launchCountKey)
        defaults.set("0.0.0-old", forKey: Self.lastPromptVersionKey)
        defaults.set(Date().addingTimeInterval(-100 * 86400), forKey: Self.lastPromptDateKey)
        XCTAssertTrue(service.isEligible)
    }

    // MARK: - isWithinCooldownWindow gating

    /// Onboarding opt-in path: fresh install, no engagement, but no prior
    /// prompt — cooldown allows the sheet to be shown.
    func test_cooldownWindow_freshInstall_returnsTrue() {
        defaults.set(Date(), forKey: Self.installDateKey)
        XCTAssertTrue(service.isWithinCooldownWindow)
    }

    /// Already prompted on the current version blocks the cooldown window
    /// even when engagement gates would otherwise pass.
    func test_cooldownWindow_promptedOnCurrentVersion_returnsFalse() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        defaults.set(currentVersion, forKey: Self.lastPromptVersionKey)
        XCTAssertFalse(service.isWithinCooldownWindow)
    }

    /// Prompt fired < 90 days ago on a previous version still blocks the
    /// cooldown window — the per-prompt minimum interval is the dominant
    /// constraint here.
    func test_cooldownWindow_recentPromptDifferentVersion_returnsFalse() {
        defaults.set("0.0.0-old", forKey: Self.lastPromptVersionKey)
        defaults.set(Date().addingTimeInterval(-30 * 86400), forKey: Self.lastPromptDateKey)
        XCTAssertFalse(service.isWithinCooldownWindow)
    }
}
