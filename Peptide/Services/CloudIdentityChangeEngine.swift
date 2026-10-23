import Foundation

/// How the device's iCloud identity moved between two observations.
enum CloudIdentityChange: Equatable, Sendable {
    case unchanged
    case signedIn
    case signedOut
    case switchedAccount
}

/// Decides what happens to the local store when the iCloud identity
/// changes (audit A116). The CloudKit and local containers share one
/// store file, so reopening it after a sign-out keeps the previous
/// account's rows on screen, and reopening it under a different account
/// can export them into that account.
enum CloudIdentityChangeEngine {

    static func change(previousSignedIn: Bool, currentSignedIn: Bool, sameAccount: Bool) -> CloudIdentityChange {
        switch (previousSignedIn, currentSignedIn) {
        case (false, false): .unchanged
        case (false, true): .signedIn
        case (true, false): .signedOut
        case (true, true): sameAccount ? .unchanged : .switchedAccount
        }
    }

    /// True when the store must stay closed until the user chooses to
    /// keep or remove what's in it: there is data, and the account it was
    /// last opened under is gone. Signing in skips the prompt only when no
    /// account was ever recorded on this install — otherwise the data may
    /// be one kept from an earlier account after a sign-out.
    static func needsUserDecision(
        _ change: CloudIdentityChange,
        storeHasData: Bool,
        hadEarlierIdentity: Bool
    ) -> Bool {
        guard storeHasData else { return false }
        switch change {
        case .unchanged: return false
        case .signedIn: return hadEarlierIdentity
        case .signedOut, .switchedAccount: return true
        }
    }
}
