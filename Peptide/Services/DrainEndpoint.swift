import Foundation

/// Shared endpoint policy for the operator-configured PII drains
/// (`AffiliateIntakeService`, `OnboardingFunnelTracker`). An endpoint
/// is usable only when it is HTTPS *and* its host is an
/// Atlas-controlled domain, so a tampered or mistyped Info.plist
/// value pointing at an arbitrary collector is rejected before any
/// data leaves the device (audit 2.3).
enum DrainEndpoint {
    /// Domains Atlas controls. An endpoint host must equal one of
    /// these or be a subdomain of one. Deploys on other hosts
    /// (e.g. *.vercel.app) must be fronted by a CNAME on an Atlas
    /// domain instead of widening this list.
    private static let allowedDomains = ["peptidesai.com", "peptidex.site"]

    /// Header carrying the rotatable drain secret — same header the
    /// AI proxy routes authenticate with, so the backend can reuse
    /// the verification machinery.
    static let authHeaderField = "X-Peptide-Proxy"

    /// Resolves and validates an endpoint from Info.plist. Absent
    /// key, empty value, non-HTTPS scheme, or a host outside
    /// `allowedDomains` all disable the drain (return nil).
    static func url(infoKey: String) -> URL? {
        validated(Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)
    }

    /// Optional rotatable shared secret for the drain endpoint.
    /// Absent → the caller sends no auth header and the backend
    /// decides whether to accept unauthenticated drains.
    static func secret(infoKey: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !raw.isEmpty else { return nil }
        return raw
    }

    /// Pure validation core, split from the Bundle read so tests can
    /// exercise the scheme/host policy directly.
    static func validated(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else {
            return nil
        }
        return url
    }
}
