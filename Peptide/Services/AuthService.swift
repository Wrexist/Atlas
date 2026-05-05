@preconcurrency import AuthenticationServices
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Manages Sign in with Apple identity and Keychain-backed credential persistence.
///
/// Fully optional — every feature works without sign-in. The stored user identifier
/// is reserved for future server-backed features; the v1.x app does not transmit it.
@MainActor @Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var isSignedIn = false
    private(set) var userIdentifier: String?
    private(set) var userEmail: String?
    private(set) var userDisplayName: String?

    /// True while an Apple Sign-In flow is in progress.
    /// UI binds to this to show a spinner and disable the button.
    private(set) var isSigningIn = false

    /// Surfaces the most recent sign-in failure so the UI can show an alert.
    /// Cleared by `clearLastError()` once the user dismisses the alert.
    private(set) var lastError: SignInError?

    enum SignInError: Equatable {
        case canceled
        case timedOut
        case failed(String)

        var title: String {
            switch self {
            case .canceled:  return "Sign-In Canceled"
            case .timedOut:  return "Sign-In Is Taking Too Long"
            case .failed:    return "Sign-In Failed"
            }
        }

        var message: String {
            switch self {
            case .canceled:
                return "You canceled the sign-in. You can try again or continue without signing in — all features work without an account."
            case .timedOut:
                return "Apple’s sign-in service didn’t respond. Check your connection or continue without signing in — all features work without an account."
            case .failed(let underlying):
                return "\(underlying) You can try again or continue without signing in — all features work without an account."
            }
        }
    }

    private static let keychainService = "com.peptidesai.app.auth"
    private static let keychainAccountID = "apple-user-id"
    private static let keychainAccountEmail = "apple-user-email"
    private static let keychainAccountName = "apple-user-name"

    /// Soft watchdog. Apple's auth daemon can hang on the system "Signing in…"
    /// sheet (seen in App Review on iPadOS 26 / Stage Manager). After this we
    /// drop our own in-progress state and surface a recoverable error, so the
    /// user is never trapped without an exit.
    private static let signInTimeout: Duration = .seconds(30)

    private var coordinator: AppleSignInCoordinator?
    private var timeoutTask: Task<Void, Never>?

    private init() {
        restoreFromKeychain()
    }

    // MARK: - Sign In

    /// Starts the Sign in with Apple flow with an explicit presentation context
    /// (required for reliable presentation on iPad / multi-scene setups).
    /// Idempotent — extra taps while a request is in flight are ignored.
    func signIn() {
        guard !isSigningIn else { return }
        lastError = nil
        isSigningIn = true

        let coordinator = AppleSignInCoordinator { [weak self] result in
            Task { @MainActor in
                self?.finishSignIn(result: result)
            }
        }
        self.coordinator = coordinator
        coordinator.start()

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.signInTimeout)
            guard let self, !Task.isCancelled, self.isSigningIn else { return }
            self.isSigningIn = false
            self.coordinator = nil
            self.lastError = .timedOut
            AppLog.auth.error("Sign in with Apple timed out (no callback within timeout window)")
        }
    }

    func clearLastError() {
        lastError = nil
    }

    /// Handles the credential returned by `ASAuthorizationController` (or by
    /// the SwiftUI `SignInWithAppleButton` for callers that still use it).
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

    private func finishSignIn(result: Result<ASAuthorization, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        coordinator = nil
        isSigningIn = false

        switch result {
        case .success:
            handleAuthorization(result)
        case .failure(let error):
            let asCode = (error as? ASAuthorizationError)?.code
            switch asCode {
            case .canceled:
                lastError = .canceled
            default:
                lastError = .failed(error.localizedDescription)
                AppLog.auth.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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

    // MARK: - Delete Account

    /// Removes the Apple ID linkage and erases user-generated content
    /// (protocols, entries, profile). Required by Apple Guideline 5.1.1(v).
    ///
    /// Without a developer-operated backend there is nothing to revoke
    /// server-side; users can revoke the Apple ID token at appleid.apple.com
    /// if desired. SwiftData mutations propagate to the user's private
    /// CloudKit zone automatically when iCloud sync is active.
    func deleteAccount() {
        SwiftDataRepository.shared.deleteAll()
        signOut()
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

// MARK: - ASAuthorizationController Coordinator

/// Drives `ASAuthorizationController` directly so we can supply an explicit
/// `presentationContextProvider`. The SwiftUI `SignInWithAppleButton` does not
/// expose this, which leaves it brittle on iPad / Stage Manager / multi-scene
/// layouts where the system can fail to find a window and hangs the
/// "Signing in…" sheet indefinitely.
@MainActor
private final class AppleSignInCoordinator: NSObject {
    typealias Completion = @Sendable (Result<ASAuthorization, Error>) -> Void

    private let completion: Completion
    private var hasFinished = false

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        completion(result)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in self.finish(.success(authorization)) }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.foregroundAnchor() }
    }

    @MainActor
    private static func foregroundAnchor() -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
        if let window = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first {
            return window
        }
        #endif
        return ASPresentationAnchor()
    }
}
