import Foundation

/// The user's one-time, explicit permission to send what they submit —
/// research-chat messages, a meal photo — to Anthropic's Claude through
/// Atlas's proxy (App Store Guideline 5.1.2(i)). Stored as the moment of
/// consent so a revoke is simply removing it. The weekly recap has its own
/// toggle and disclosure and does not read this.
enum AIDataConsent {
    private static let key = "aiDataSharingConsentAt"

    static var isGranted: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static func grant() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    static func revoke() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
