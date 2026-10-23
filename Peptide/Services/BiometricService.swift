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
        default: String(localized: "Biometrics")
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

    func authenticate() async -> BiometricOutcome {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use Passcode")

        do {
            let passed = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock Atlas")
            )
            return passed ? .success : .failed
        } catch {
            let outcome = (error as? LAError).map { BiometricOutcome(code: $0.code) } ?? .failed
            // A cancel is expected and routine; log it at debug.
            if outcome == .cancelled {
                AppLog.biometrics.debug("User cancelled biometric prompt")
            } else {
                AppLog.biometrics.error("Authentication failed: \(error.localizedDescription, privacy: .public)")
            }
            return outcome
        }
    }
}

/// How an unlock attempt ended.
enum BiometricOutcome: Equatable, Sendable {
    case success
    /// The user, the app or the system dismissed the prompt.
    case cancelled
    /// Not recognised, locked out or similar; another attempt can pass.
    case failed
    /// The device has no passcode, so no owner authentication can ever
    /// pass and a lock behind it could never be cleared.
    case unavailable

    init(code: LAError.Code) {
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            self = .cancelled
        case .passcodeNotSet:
            self = .unavailable
        default:
            self = .failed
        }
    }
}
