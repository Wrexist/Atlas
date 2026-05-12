@preconcurrency import LocalAuthentication

/// Soft privacy screen, not a crypto-bound vault. Gates the app's UI
/// behind a Face ID / Touch ID / passcode check at launch, but the
/// underlying SwiftData container and Keychain items are *not* tied
/// to biometrics — a passcode shoulder-surf bypasses the gate. The
/// settings copy reflects this honestly; v2 work to bind SwiftData
/// behind a SecAccessControl-protected key is tracked separately.
@MainActor @Observable
final class BiometricService {
    static let shared = BiometricService()

    private(set) var isAvailable = false
    private(set) var biometryType: LABiometryType = .none

    var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Biometrics"
        }
    }

    var biometryIcon: String {
        switch biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    private init() {
        checkAvailability()
    }

    func checkAvailability() {
        let context = LAContext()
        var error: NSError?
        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = context.biometryType
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock PeptideX"
            )
        } catch {
            // LAError.userCancel is expected and routine; log at debug.
            // Other failures (lockout, biometryLockout, system cancel) at error.
            if let laError = error as? LAError, laError.code == .userCancel {
                AppLog.biometrics.debug("User cancelled biometric prompt")
            } else {
                AppLog.biometrics.error("Authentication failed: \(error.localizedDescription, privacy: .public)")
            }
            return false
        }
    }
}
