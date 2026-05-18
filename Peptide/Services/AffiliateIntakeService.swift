import Foundation

/// Drains a locally-stored `AffiliateApplication` to the configured
/// creator-program intake endpoint. Same mechanism as
/// `OnboardingFunnelTracker.drainIfReady`: opt-in via an Info.plist
/// key, HTTPS-only, retry-on-failure via "did we already drain?"
/// guard so a successful POST isn't re-attempted on every launch.
///
/// The transport stays local-only until the backend exists — when
/// the Info.plist key is absent the service is a no-op.
@MainActor
enum AffiliateIntakeService {
    /// Info.plist key holding the intake endpoint. Required: `https://`
    /// scheme. Absent / empty disables drain entirely.
    private static let endpointInfoKey = "AffiliateIntakeEndpoint"

    /// Stamped after a successful drain. Keyed by the application's
    /// `submittedAt` so a resubmission (different timestamp) is
    /// treated as a fresh row and drained again.
    private static let lastDrainedAtKey = "affiliate.intake.drainedAt.v1"

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
        guard let raw = Bundle.main.object(forInfoDictionaryKey: endpointInfoKey) as? String,
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
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
