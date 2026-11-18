import Foundation

/// How the device's iCloud identity moved between two observations.
enum CloudIdentityChange: Equatable, Sendable {
    case unchanged
    case signedIn
    case signedOut
    case switchedAccount
    /// Signed in, but the store was last opened under an account an
    /// older build recorded only by its ubiquity token, which no longer
    /// matches — possibly the same account, possibly another.
    case unverified
}

/// The CloudKit account the shared store was last opened under, as this
/// install recorded it.
enum RecordedCloudAccount: Equatable, Sendable {
    case noAccount
    /// The account's CloudKit user record name.
    case account(String)
    /// Opened under an account recorded only by its ubiquity token.
    case unidentified
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

    /// `current` is the signed-in account's CloudKit user record name.
    /// iCloud Drive's ubiquity token plays no part: it is nil whenever
    /// Drive is off, although the CloudKit account is unchanged.
    static func change(from recorded: RecordedCloudAccount, to current: String?) -> CloudIdentityChange {
        if recorded == .unidentified, current != nil { return .unverified }
        var previous: String?
        if case .account(let name) = recorded { previous = name }
        return change(
            previousSignedIn: recorded != .noAccount,
            currentSignedIn: current != nil,
            sameAccount: previous != nil && previous == current
        )
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
        case .signedOut, .switchedAccount, .unverified: return true
        }
    }

    /// True when the device-local records (recaps, Apple Health
    /// weigh-ins, scan history) must be erased as the store opens. They
    /// belong to whoever was signed in, so a sign-out or switch hands
    /// them on, but while the store is held the user's Keep or Remove
    /// decides instead.
    static func forgetsDeviceLocalRecords(_ change: CloudIdentityChange, heldForDecision: Bool) -> Bool {
        guard !heldForDecision else { return false }
        switch change {
        case .unchanged, .signedIn, .unverified: return false
        case .signedOut, .switchedAccount: return true
        }
    }
}
