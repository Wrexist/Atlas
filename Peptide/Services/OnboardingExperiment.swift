import Foundation
import CryptoKit

/// Deterministic per-install A/B assignment for onboarding variants.
/// Hash-of-install-ID maps each user into the same variant on every
/// launch, so we don't flip the flow under them between sessions.
///
/// Strictly local — no backend, no network. The assigned variant is
/// recorded in `OnboardingFunnelTracker.recordEvent` so a future
/// analytics drain can correlate variants with conversion rates.
///
/// Add new experiments by extending `Experiment`. Each experiment owns
/// its own UserDefaults key so a launched experiment can be "frozen"
/// to control once enough data is collected (set `frozenToControl`).
@MainActor
enum OnboardingExperiment {

    /// Currently-running experiments. Add a case here, give it a
    /// stable raw value (used both as the UserDefaults suffix and the
    /// funnel event payload), then read it via `variant(for:)`.
    enum Experiment: String, CaseIterable {
        /// Paywall tier ordering: control shows yearly first (current
        /// default), variantA shows monthly first with the trial more
        /// prominent. Measures whether the savings anchor or the
        /// trial framing wins.
        case paywallTierOrder = "paywall_tier_order"
    }

    enum Variant: String, Codable, Sendable {
        case control
        case variantA
    }

    /// Returns the variant for the given experiment, lazily assigning
    /// (and persisting) on first read. Idempotent — same install ID
    /// always returns the same variant.
    static func variant(for experiment: Experiment) -> Variant {
        let key = "experiment.\(experiment.rawValue).v1"
        if let stored = UserDefaults.standard.string(forKey: key),
           let parsed = Variant(rawValue: stored) {
            return parsed
        }
        let assignment = assign(for: experiment)
        UserDefaults.standard.set(assignment.rawValue, forKey: key)
        OnboardingFunnelTracker.recordEvent(
            "experiment_\(experiment.rawValue)_\(assignment.rawValue)"
        )
        return assignment
    }

    /// Deterministic assignment via SHA-256 of (installID + salt). A
    /// 50/50 split today — adjust the modulus for finer-grained
    /// rollouts (e.g. % 10 < 1 for a 10% pilot). SHA-256 is used
    /// instead of `String.hashValue` because Swift randomises hashValue
    /// per process launch — a future refactor that drops the
    /// UserDefaults cache, or a test that calls assign directly, would
    /// produce nondeterministic results with the old impl (audit
    /// security M-4 / code-review #13).
    private static func assign(for experiment: Experiment) -> Variant {
        let bytes = Data((installID + experiment.rawValue).utf8)
        let digest = SHA256.hash(data: bytes)
        let leading = digest.withUnsafeBytes { $0.load(as: UInt64.self) }
        return leading.isMultiple(of: 2) ? .control : .variantA
    }

    /// Stable per-install identifier. UUID-on-first-launch, then
    /// frozen for the lifetime of the install. Distinct from the
    /// onboarding session ID so a user who resets onboarding stays
    /// in the same experiment cohort.
    private static var installID: String {
        let key = "experiment.install_id.v1"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    /// Test-only — wipes the install ID and all assignments so each
    /// test runs against a fresh deterministic seed.
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: "experiment.install_id.v1")
        for experiment in Experiment.allCases {
            UserDefaults.standard.removeObject(forKey: "experiment.\(experiment.rawValue).v1")
        }
    }
}
