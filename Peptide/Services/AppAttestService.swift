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

    /// The launch's one registration attempt, shared by every caller
    /// so concurrent AI requests join it instead of racing it, and a
    /// failing backend can't add a round trip to every AI call.
    private var registration: Task<String?, Never>?

    /// Server time minus device time, learned from an `attest_clock`
    /// refusal, so a device whose clock is off still stamps assertions
    /// inside the proxy's freshness window. Not persisted: a clock the
    /// user fixes mid-session would otherwise be pushed off again.
    private var serverClockOffset: TimeInterval = 0

    private init() {}

    private var endpoint: URL? {
        MealScannerService.urlSetting(forKey: "APP_ATTEST_ENDPOINT")
    }

    private var secret: String? {
        MealScannerService.stringSetting(forKey: "APP_ATTEST_SECRET")
    }

    private var isAvailable: Bool {
        endpoint != nil && secret != nil && DCAppAttestService.shared.isSupported
    }

    /// Starts registration at launch, off the request path, so the
    /// first research question or meal scan doesn't wait on two
    /// network round trips and a Secure Enclave attestation.
    func warmUp() {
        guard isAvailable, storedRegisteredKeyId == nil else { return }
        _ = startRegistrationIfNeeded()
    }

    /// Assertion headers for a proxied AI request, or nil whenever
    /// App Attest can't contribute (simulator, no config, key not
    /// yet registered, Apple/Secure Enclave failure). Callers attach
    /// what they get and always proceed. Without a registered key this
    /// returns nil at once so the request goes out on the shared
    /// secret; only the retry after an `attest_required` 401 passes
    /// `waitForRegistration`, since enforce mode rejects it otherwise.
    func assertionHeaders(waitForRegistration: Bool = false) async -> [String: String]? {
        guard isAvailable else { return nil }
        guard let keyId = await registeredKeyId(waiting: waitForRegistration) else { return nil }

        // 16 random bytes + big-endian millisecond timestamp. The
        // server bounds staleness; the assertion counter handles
        // replay. This blob authenticates the caller, not the body.
        var clientData = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let stampedAt = Date().addingTimeInterval(serverClockOffset)
        withUnsafeBytes(of: UInt64(stampedAt.timeIntervalSince1970 * 1000).bigEndian) {
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
            // device). Forget it so the next assertionHeaders() call
            // re-registers without waiting for a relaunch.
            AppLog.auth.warning("app-attest key invalid; clearing for re-registration")
            invalidateRegistration()
            return nil
        } catch {
            AppLog.auth.warning("app-attest assertion failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    // MARK: - Registration

    /// True when a 401 body is the proxy's `attest_required` answer:
    /// it no longer knows this install's key (a store flush, a moved
    /// database), so the caller should invalidate and retry once.
    nonisolated static func isAttestRejection(_ body: Data) -> Bool {
        rejectionCode(body) == "attest_required"
    }

    /// True when a 401 body is the proxy's `attest_clock` answer: the
    /// key is fine but the device clock is outside the freshness window.
    nonisolated static func isClockRejection(_ body: Data) -> Bool {
        rejectionCode(body) == "attest_clock"
    }

    private nonisolated static func rejectionCode(_ body: Data) -> String? {
        struct Envelope: Decodable {
            struct Detail: Decodable { let code: String? }
            let error: Detail
        }
        return (try? JSONDecoder().decode(Envelope.self, from: body))?.error.code
    }

    /// Acts on a proxy 401 and reports whether one retry can succeed:
    /// `attest_required` drops the key so the retry registers a fresh
    /// one; `attest_clock` keeps the key and adopts the server's clock
    /// from the response's `Date` header (`serverDate`). Re-registering
    /// on a clock refusal would mint a new key that fails the same way.
    func recover(fromRejection body: Data, serverDate: String?) -> Bool {
        if Self.isAttestRejection(body) {
            invalidateRegistration()
            return true
        }
        guard Self.isClockRejection(body),
              let serverDate,
              let offset = Self.clockOffset(serverDate: serverDate, now: Date()) else { return false }
        serverClockOffset = offset
        return true
    }

    /// Server time minus `now`, from an HTTP `Date` header
    /// (`Sun, 06 Nov 1994 08:49:37 GMT`), or nil when it doesn't parse.
    nonisolated static func clockOffset(serverDate: String, now: Date) -> TimeInterval? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let server = formatter.date(from: serverDate) else { return nil }
        return server.timeIntervalSince(now)
    }

    /// Forgets the key and its registration, so the next
    /// assertionHeaders() call registers a fresh key. A key Apple has
    /// already attested can't be attested again, hence a new one.
    func invalidateRegistration() {
        UserDefaults.standard.removeObject(forKey: keyIdDefaultsKey)
        UserDefaults.standard.removeObject(forKey: registeredDefaultsKey)
        registration = nil
    }

    private var storedRegisteredKeyId: String? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: registeredDefaultsKey) else { return nil }
        return defaults.string(forKey: keyIdDefaultsKey)
    }

    private func registeredKeyId(waiting: Bool) async -> String? {
        if let keyId = storedRegisteredKeyId { return keyId }
        let registration = startRegistrationIfNeeded()
        return waiting ? await registration.value : nil
    }

    private func startRegistrationIfNeeded() -> Task<String?, Never> {
        if let registration { return registration }
        let task = Task { await self.register() }
        registration = task
        return task
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
            invalidateRegistration()
            return nil
        } catch {
            AppLog.auth.warning("app-attest registration failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
