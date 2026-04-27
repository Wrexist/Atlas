@preconcurrency import AuthenticationServices
import Security

/// Manages Sign in with Apple identity and Keychain-backed credential persistence.
///
/// Fully optional — every feature works without sign-in. The stored user identifier
/// gates cloud sync eligibility in future releases.
@MainActor @Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var isSignedIn = false
    private(set) var userIdentifier: String?
    private(set) var userEmail: String?
    private(set) var userDisplayName: String?

    private static let keychainService = "com.peptidesai.app.auth"
    private static let keychainAccountID = "apple-user-id"
    private static let keychainAccountEmail = "apple-user-email"
    private static let keychainAccountName = "apple-user-name"

    private init() {
        restoreFromKeychain()
    }

    // MARK: - Sign In

    /// Handles the credential returned by `SignInWithAppleButton`.
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        let userId = credential.user

        // Guard against PII carryover: only reuse cached email/name when the
        // stored user ID matches the current credential (Apple only sends
        // name/email on the very first authorization).
        let previousUserId = Self.readKeychain(account: Self.keychainAccountID)
        let sameAccount = (previousUserId == userId)

        let email = credential.email ?? (sameAccount ? Self.readKeychain(account: Self.keychainAccountEmail) : nil)
        let name: String? = {
            if let components = credential.fullName,
               let formatted = PersonNameComponentsFormatter().string(for: components),
               !formatted.trimmingCharacters(in: .whitespaces).isEmpty {
                return formatted
            }
            return sameAccount ? Self.readKeychain(account: Self.keychainAccountName) : nil
        }()

        // Persist user ID first — abort sign-in if it can't be stored.
        // Only clear old profile data after confirming the new ID landed safely.
        guard Self.writeKeychain(value: userId, account: Self.keychainAccountID) == errSecSuccess else { return }
        if !sameAccount {
            Self.deleteKeychain(account: Self.keychainAccountEmail)
            Self.deleteKeychain(account: Self.keychainAccountName)
        }
        if let email { Self.writeKeychain(value: email, account: Self.keychainAccountEmail) }
        if let name { Self.writeKeychain(value: name, account: Self.keychainAccountName) }

        userIdentifier  = userId
        userEmail       = email
        userDisplayName = name
        isSignedIn      = true
    }

    // MARK: - Sign Out

    func signOut() {
        Self.deleteKeychain(account: Self.keychainAccountID)
        Self.deleteKeychain(account: Self.keychainAccountEmail)
        Self.deleteKeychain(account: Self.keychainAccountName)

        userIdentifier  = nil
        userEmail       = nil
        userDisplayName = nil
        isSignedIn      = false
    }

    // MARK: - Credential Validation

    /// Checks whether the stored Apple ID credential is still valid.
    /// Sign out only on definitive negative states (notFound / revoked / transferred);
    /// transient errors keep the session and log for diagnostics.
    func validateCredential() async {
        guard let userId = userIdentifier else { return }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)
            guard userIdentifier == userId else { return }
            switch state {
            case .authorized:
                return
            case .notFound, .revoked, .transferred:
                signOut()
            @unknown default:
                AppLog.auth.error("Unknown credential state \(state.rawValue, privacy: .public); keeping session")
            }
        } catch {
            AppLog.auth.error("credentialState lookup failed (keeping session): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Keychain Restore

    private func restoreFromKeychain() {
        guard let userId = Self.readKeychain(account: Self.keychainAccountID) else { return }
        userIdentifier  = userId
        userEmail       = Self.readKeychain(account: Self.keychainAccountEmail)
        userDisplayName = Self.readKeychain(account: Self.keychainAccountName)
        isSignedIn      = true
    }

    // MARK: - Keychain Helpers

    @discardableResult
    private static func writeKeychain(value: String, account: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]

        // Update-first upsert: avoids a window where the item is absent.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return errSecSuccess }
        if updateStatus != errSecItemNotFound { return updateStatus }

        var addQuery = query
        addQuery[kSecValueData as String]      = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
