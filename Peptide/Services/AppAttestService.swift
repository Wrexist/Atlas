import CryptoKit
import DeviceCheck
import Foundation

/// Client side of the App Attest gate on the proxy routes. Generates
/// a Secure-Enclave key once per install, registers it with
/// `/api/attest-register` (challenge → attestation), then attaches a
/// per-request assertion so the proxy can verify the call comes from
/// a genuine Atlas install — the shared secret alone no longer has
/// to carry the whole defense.
///
/// Config (Info.plist or scheme env): `APP_ATTEST_ENDPOINT` (the
/// attest-register URL) + `APP_ATTEST_SECRET` (the shared proxy
/// secret). Either absent → the service is inert. Every path here is
/// best-effort: failures return nil and never block an AI request —
/// the server decides whether assertions are required
/// (`APP_ATTEST_MODE` on the deployment).
actor AppAttestService {
    static let shared = AppAttestService()

    /// The keyId is not a secret (the private key never leaves the
    /// Secure Enclave), so UserDefaults is the right durability.
    private let keyIdDefaultsKey = "appattest.keyId.v1"
    private let registeredDefaultsKey = "appattest.registered.v1"

    /// One registration attempt per launch so a failing backend
    /// can't add a round trip to every AI call.
    private var registrationAttemptedThisLaunch = false

    private init() {}

    private var endpoint: URL? {
        MealScannerService.urlSetting(forKey: "APP_ATTEST_ENDPOINT")
    }

    private var secret: String? {
        MealScannerService.stringSetting(forKey: "APP_ATTEST_SECRET")
    }

    /// Assertion headers for a proxied AI request, or nil whenever
    /// App Attest can't contribute (simulator, no config, key not
    /// yet registered, Apple/Secure Enclave failure). Callers attach
    /// what they get and always proceed.
    func assertionHeaders() async -> [String: String]? {
        guard endpoint != nil, secret != nil,
              DCAppAttestService.shared.isSupported else { return nil }
        guard let keyId = await registeredKeyId() else { return nil }

        // 16 random bytes + big-endian millisecond timestamp. The
        // server bounds staleness; the assertion counter handles
        // replay. This blob authenticates the caller, not the body.
        var clientData = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        withUnsafeBytes(of: UInt64(Date().timeIntervalSince1970 * 1000).bigEndian) {
            clientData.append(contentsOf: $0)
        }

        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(
                keyId,
                clientDataHash: Data(SHA256.hash(data: clientData))
            )
            return [
                "X-Attest-Key-Id": keyId,
                "X-Attest-Assertion": assertion.base64EncodedString(),
                "X-Attest-Client-Data": clientData.base64EncodedString(),
            ]
        } catch let error as DCError where error.code == .invalidKey {
            // The key lost Apple's trust (e.g. restore onto a new
            // device). Forget it; clearStoredKey resets the
            // attempt guard so the next assertionHeaders() call
            // re-registers without waiting for a relaunch.
            AppLog.auth.warning("app-attest key invalid; clearing for re-registration")
            clearStoredKey()
            return nil
        } catch {
            AppLog.auth.warning("app-attest assertion failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    // MARK: - Registration

    private func registeredKeyId() async -> String? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: registeredDefaultsKey),
           let keyId = defaults.string(forKey: keyIdDefaultsKey) {
            return keyId
        }
        guard !registrationAttemptedThisLaunch else { return nil }
        // Set before the first await: actor reentrancy would
        // otherwise let a second AI call start a parallel
        // registration against the same key.
        registrationAttemptedThisLaunch = true
        return await register()
    }

    private struct ChallengeResponse: Decodable {
        let challengeId: String
        let challenge: String
    }

    private func register() async -> String? {
        guard let endpoint, let secret else { return nil }
        do {
            var challengeRequest = URLRequest(url: endpoint)
            challengeRequest.timeoutInterval = 10
            challengeRequest.setValue(secret, forHTTPHeaderField: "X-Peptide-Proxy")
            let (challengeData, challengeResponse) = try await URLSession.shared.data(for: challengeRequest)
            guard (challengeResponse as? HTTPURLResponse)?.statusCode == 200,
                  let parsed = try? JSONDecoder().decode(ChallengeResponse.self, from: challengeData),
                  let challenge = Data(base64Encoded: parsed.challenge) else {
                AppLog.auth.warning("app-attest challenge fetch failed")
                return nil
            }

            // Reuse a generated-but-unregistered key so an aborted
            // first run doesn't mint Secure Enclave keys forever.
            let keyId: String
            if let existing = UserDefaults.standard.string(forKey: keyIdDefaultsKey) {
                keyId = existing
            } else {
                keyId = try await DCAppAttestService.shared.generateKey()
                UserDefaults.standard.set(keyId, forKey: keyIdDefaultsKey)
            }

            let attestation = try await DCAppAttestService.shared.attestKey(
                keyId,
                clientDataHash: Data(SHA256.hash(data: challenge))
            )

            var registerRequest = URLRequest(url: endpoint)
            registerRequest.httpMethod = "POST"
            registerRequest.timeoutInterval = 10
            registerRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            registerRequest.setValue(secret, forHTTPHeaderField: "X-Peptide-Proxy")
            registerRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "keyId": keyId,
                "challengeId": parsed.challengeId,
                "attestation": attestation.base64EncodedString(),
            ])
            let (_, registerResponse) = try await URLSession.shared.data(for: registerRequest)
            guard (registerResponse as? HTTPURLResponse)?.statusCode == 200 else {
                AppLog.auth.warning("app-attest registration rejected")
                return nil
            }

            UserDefaults.standard.set(true, forKey: registeredDefaultsKey)
            AppLog.auth.info("app-attest key registered")
            return keyId
        } catch let error as DCError where error.code == .invalidKey {
            clearStoredKey()
            return nil
        } catch {
            AppLog.auth.warning("app-attest registration failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func clearStoredKey() {
        UserDefaults.standard.removeObject(forKey: keyIdDefaultsKey)
        UserDefaults.standard.removeObject(forKey: registeredDefaultsKey)
        // Reset the per-launch guard too — otherwise a key invalidated
        // mid-session would never re-register until the next cold
        // launch, silently dropping App Attest for the rest of the run.
        registrationAttemptedThisLaunch = false
    }
}
