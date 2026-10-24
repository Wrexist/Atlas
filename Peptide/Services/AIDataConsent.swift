import Foundation

/// The user's one-time, explicit permission to send what they submit —
/// research-chat messages, a meal photo — to Anthropic's Claude through
/// Atlas's proxy (App Store Guideline 5.1.2(i)). Stored as the moment of
/// consent so a revoke is simply removing it. The weekly recap also sends
/// data, so turning it on asks for this consent and its proxy call is
/// skipped without it.
///
/// The diet coach and Ask Atlas also send a summary the user never typed (a
/// 7-day nutrition summary; their Biological Age and its signals), so each
/// needs its own grant on top of the general one: consent given to the
/// research chat covers neither summary.
enum AIDataConsent {
    private static let key = "aiDataSharingConsentAt"
    private static let coachSummaryKey = "aiCoachSummaryConsentAt"
    private static let biologySummaryKey = "aiBiologySummaryConsentAt"

    static var isGranted: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static var isCoachSummaryGranted: Bool {
        isGranted && UserDefaults.standard.object(forKey: coachSummaryKey) != nil
    }

    static var isBiologySummaryGranted: Bool {
        isGranted && UserDefaults.standard.object(forKey: biologySummaryKey) != nil
    }

    /// Whether a request may leave the device with a summary on `topic`
    /// attached; nil for the user's own messages only.
    static func allowsSend(attaching topic: AIResearchService.Brief.Topic?) -> Bool {
        switch topic {
        case nil:        isGranted
        case .nutrition: isCoachSummaryGranted
        case .biology:   isBiologySummaryGranted
        }
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

    /// Same as the coach: allowing the Biology summary covers the chat
    /// messages too.
    static func grantBiologySummary() {
        grant()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: biologySummaryKey)
    }

    static func revoke() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: coachSummaryKey)
        UserDefaults.standard.removeObject(forKey: biologySummaryKey)
    }
}
