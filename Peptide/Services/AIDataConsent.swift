import Foundation

/// The user's one-time, explicit permission to send what they submit —
/// research-chat messages, a meal photo — to Anthropic's Claude through
/// Atlas's proxy (App Store Guideline 5.1.2(i)). Stored as the moment of
/// consent so a revoke is simply removing it. The weekly recap also sends
/// data, so turning it on asks for this consent and its proxy call is
/// skipped without it.
///
/// The diet coach also sends a 7-day nutrition summary the user never typed,
/// so it needs its own grant on top of the general one: consent given to the
/// research chat does not cover that summary.
enum AIDataConsent {
    private static let key = "aiDataSharingConsentAt"
    private static let coachSummaryKey = "aiCoachSummaryConsentAt"

    static var isGranted: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static var isCoachSummaryGranted: Bool {
        isGranted && UserDefaults.standard.object(forKey: coachSummaryKey) != nil
    }

    /// Whether a request may leave the device — with the coach summary
    /// attached when `includesCoachSummary`.
    static func allowsSend(includesCoachSummary: Bool) -> Bool {
        includesCoachSummary ? isCoachSummaryGranted : isGranted
    }

    static func grant() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// Allowing the coach disclosure covers the chat messages too, so this
    /// records both grants.
    static func grantCoachSummary() {
        grant()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: coachSummaryKey)
    }

    static func revoke() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: coachSummaryKey)
    }
}
