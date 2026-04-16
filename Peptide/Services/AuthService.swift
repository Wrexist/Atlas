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
        if !sameAccount {
            Self.deleteKeychain(account: Self.keychainAccountEmail)
            Self.deleteKeychain(account: Self.keychainAccountName)
        }

        let email = credential.email ?? (sameAccount ? Self.readKeychain(account: Self.keychainAccountEmail) : nil)
        let name: String? = {
            if let components = credential.fullName,
               let formatted = PersonNameComponentsFormatter().string(for: components),
               !formatted.trimmingCharacters(in: .whitespaces).isEmpty {
                return formatted
            }
            return sameAccount ? Self.readKeychain(account: Self.keychainAccountName) : nil
        }()

        // Persist to Keychain — abort sign-in if the user ID can't be stored.
        guard Self.writeKeychain(value: userId, account: Self.keychainAccountID) == errSecSuccess else { return }
        if let email  { Self.writeKeychain(value: email, account: Self.keychainAccountEmail) }
        if let name   { Self.writeKeychain(value: name, account: Self.keychainAccountName) }

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
    /// If the user revoked app access in Settings, this signs them out.
    func validateCredential() async {
        guard let userId = userIdentifier else { return }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)
            guard userIdentifier == userId else { return }
            if state != .authorized {
                signOut()
            }
        } catch {
            // Network error — keep signed in, recheck next launch
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
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]

        // Delete existing item first (upsert pattern)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String]          = data
        addQuery[kSecAttrAccessible as String]     = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
