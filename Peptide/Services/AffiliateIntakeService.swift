import Foundation

/// Drains a locally-stored `AffiliateApplication` to the configured
/// creator-program intake endpoint. Same mechanism as
/// `OnboardingFunnelTracker.drainIfReady`: opt-in via an Info.plist
/// key, HTTPS + Atlas-domain only (`DrainEndpoint`), authenticated
/// with the rotatable drain secret when configured, retry-on-failure
/// via "did we already drain?" guard so a successful POST isn't
/// re-attempted on every launch.
///
/// The transport stays local-only until the backend exists — when
/// the Info.plist key is absent the service is a no-op.
@MainActor
enum AffiliateIntakeService {
    /// Info.plist key holding the intake endpoint. Must pass
    /// `DrainEndpoint` validation (HTTPS, Atlas-controlled host).
    /// Absent / empty / off-domain disables drain entirely.
    private static let endpointInfoKey = "AffiliateIntakeEndpoint"

    /// Info.plist key holding the optional rotatable drain secret,
    /// echoed as `X-Peptide-Proxy` so the intake backend can reject
    /// anonymous POSTs.
    private static let secretInfoKey = "AffiliateIntakeSecret"

    /// Stamped after a successful drain. Keyed by the application's
    /// `submittedAt` so a resubmission (different timestamp) is
    /// treated as a fresh row and drained again.
    private static let lastDrainedAtKey = "affiliate.intake.drainedAt.v1"

    /// True when this build carries a valid intake endpoint. The
    /// apply sheet keys its transmission disclosure on this so users
    /// are told their application leaves the device before they
    /// submit — and aren't told so when it doesn't.
    static var drainConfigured: Bool { destinationURL != nil }

    static func drainIfReady(_ application: AffiliateApplication?) async {
        guard let application else { return }
        guard let url = destinationURL else { return }
        if alreadyDrained(application) { return }

        guard let body = try? JSONEncoder.iso8601.encode(application) else {
            AppLog.persistence.warning("affiliate intake: encode failed")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = DrainEndpoint.secret(infoKey: secretInfoKey) {
            request.setValue(secret, forHTTPHeaderField: DrainEndpoint.authHeaderField)
        }
        request.httpBody = body
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                AppLog.persistence.warning("affiliate intake rejected by server")
                return
            }
            UserDefaults.standard.set(application.submittedAt, forKey: lastDrainedAtKey)
            AppLog.persistence.info("affiliate intake drained")
        } catch {
            AppLog.persistence.warning(
                "affiliate intake POST failed: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private static var destinationURL: URL? {
        DrainEndpoint.url(infoKey: endpointInfoKey)
    }

    private static func alreadyDrained(_ application: AffiliateApplication) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastDrainedAtKey) as? Date else {
            return false
        }
        // Treat sub-second drift as equal — JSONEncoder/Decoder can lose
        // sub-millisecond precision when the timestamp round-trips
        // through the body. A 1s tolerance avoids false re-drains.
        return abs(application.submittedAt.timeIntervalSince(last)) < 1.0
    }
}

private extension JSONEncoder {
    /// Shared encoder with ISO 8601 dates — matches the existing
    /// onboarding-funnel drain so the backend can parse both
    /// payloads with the same date strategy.
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
