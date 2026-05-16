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
        // Observe credential revocation so a user who pulls the app
        // off their Apple ID via appleid.apple.com gets signed out
        // immediately. Previously the session lingered as
        // `isSignedIn = true` until the user happened to open
        // Profile (the only call site for `validateCredential`).
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.signOut()
            }
        }
        // Defensive re-check on init: a credential that was revoked
        // while the app was killed never produced a notification, so
        // restoreFromKeychain just trusted the stored ID. Kick a
        // background validation so the UI corrects itself shortly
        // after launch.
        Task { @MainActor [weak self] in
            await self?.validateCredential()
        }
    }

    // MARK: - Sign In

    /// Starts the Sign in with Apple flow with an explicit presentation context
    /// (required for reliable presentation on iPad / multi-scene setups).
    /// Idempotent — extra taps while a request is in flight are ignored.
    func signIn() {
        guard !isSigningIn else { return }
        lastError = nil
        isSigningIn = true

        AppLog.auth.info("Sign in with Apple: starting request")
        let coordinator = AppleSignInCoordinator { [weak self] result in
            self?.finishSignIn(result: result)
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
    @discardableResult
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) -> Bool {
        guard case .success(let authorization) = result else { return false }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            AppLog.auth.error("Authorization succeeded but credential was not ASAuthorizationAppleIDCredential")
            return false
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

        // Persist user ID first. If Keychain is unavailable, still set the
        // in-memory session so the UI advances — the user is authenticated
        // for this launch even if persistence failed.
        let writeStatus = Self.writeKeychain(value: userId, account: Self.keychainAccountID)
        if writeStatus != errSecSuccess {
            AppLog.auth.error("Keychain write failed (\(writeStatus, privacy: .public)); proceeding with in-memory session")
        } else if !sameAccount {
            Self.deleteKeychain(account: Self.keychainAccountEmail)
            Self.deleteKeychain(account: Self.keychainAccountName)
        }
        if let email { Self.writeKeychain(value: email, account: Self.keychainAccountEmail) }
        if let name { Self.writeKeychain(value: name, account: Self.keychainAccountName) }

        userIdentifier  = userId
        userEmail       = email
        userDisplayName = name
        isSignedIn      = true
        AppLog.auth.info("Sign in with Apple: session established")
        return true
    }

    private func finishSignIn(result: Result<ASAuthorization, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        coordinator = nil
        isSigningIn = false

        switch result {
        case .success:
            AppLog.auth.info("Sign in with Apple: received success callback")
            if !handleAuthorization(result) {
                lastError = .failed("Could not read your Apple ID credential.")
            }
        case .failure(let error):
            let asCode = (error as? ASAuthorizationError)?.code
            switch asCode {
            case .canceled:
                AppLog.auth.info("Sign in with Apple: user canceled")
                lastError = .canceled
            default:
                AppLog.auth.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .private)")
                lastError = .failed(error.localizedDescription)
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
        // Guarded so a guest session (no Sign in with Apple) can't accidentally
        // wipe local data via this entry point. Apple Guideline 5.1.1(v)
        // applies to *account* deletion — guests have no account to delete and
        // can clear their data via "Reset App Data" in Settings.
        guard isSignedIn else {
            AppLog.auth.warning("deleteAccount called without an active sign-in; ignored.")
            return
        }
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
            AppLog.auth.error("credentialState lookup failed (keeping session): \(error.localizedDescription, privacy: .private)")
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
        // `AfterFirstUnlockThisDeviceOnly`: never syncs to iCloud Keychain
        // or restores to another device — so Apple-relayed email/name PII
        // stays bound to the original phone — while still being readable
        // after the first post-reboot unlock, which keeps widgets, the
        // Watch app, and HealthKit background observers working.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            // SecItemUpdate does NOT change `kSecAttrAccessible` on an
            // existing item — the accessibility class is fixed at
            // creation time. An item written by an older build (with
            // the default `WhenUnlocked` class) would silently keep
            // that class after the update and remain unreadable from
            // background observers. Verify and re-create if the class
            // doesn't match.
            if !hasExpectedAccessibility(account: account) {
                AppLog.auth.error("Keychain item for \(account, privacy: .public) had wrong accessibility; recreating")
                let deleteStatus = SecItemDelete(query as CFDictionary)
                guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                    return deleteStatus
                }
                var addQuery = query
                addQuery[kSecValueData as String]      = data
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                return SecItemAdd(addQuery as CFDictionary, nil)
            }
            return errSecSuccess
        }
        if updateStatus != errSecItemNotFound { return updateStatus }

        var addQuery = query
        addQuery[kSecValueData as String]      = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Reads the item's `kSecAttrAccessible` value and compares to the
    /// expected class. Used to detect items written by older builds
    /// that didn't specify accessibility (default = `WhenUnlocked`)
    /// — those need to be deleted + re-added to actually change the
    /// class, since `SecItemUpdate` won't.
    private static func hasExpectedAccessibility(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let attrs = result as? [String: Any],
              let cls = attrs[kSecAttrAccessible as String]
        else { return true }  // Unknown — don't churn unnecessarily.
        return (cls as? String) == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
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
    typealias Completion = @MainActor (Result<ASAuthorization, Error>) -> Void

    private let completion: Completion
    /// Strong reference to the in-flight controller. Apple's docs require
    /// holding a strong reference for the duration of the request — without
    /// this, the controller can be deallocated before its delegate fires and
    /// the success callback is silently dropped (observed: system sheet
    /// shows "Klar" / done, app does not advance).
    private var controller: ASAuthorizationController?
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
        self.controller = controller
        controller.performRequests()
    }

    fileprivate func finish(_ result: Result<ASAuthorization, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        controller = nil
        completion(result)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    // UIKit calls these on the main thread; resolve synchronously to avoid
    // an async hop that could be reordered or dropped under concurrency
    // diagnostics. `assumeIsolated` is safe here because the framework
    // contract is that delegate callbacks land on the main thread.

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            AppLog.auth.info("ASAuthorizationController: didCompleteWithAuthorization")
            self.finish(.success(authorization))
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            AppLog.auth.info("ASAuthorizationController: didCompleteWithError \(error.localizedDescription, privacy: .private)")
            self.finish(.failure(error))
        }
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
