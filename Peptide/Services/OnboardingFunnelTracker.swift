import Foundation

/// Local-only per-step funnel tracking for onboarding. Records the first
/// entry timestamp for each step into UserDefaults so a single completed
/// run can be reconstructed after the fact, and emits an `AppLog.onboarding`
/// signpost so Console.app sessions show the flow in real time.
///
/// Intentionally no PII — event names are fixed identifiers, never user
/// content. The snapshot stays on-device unless BOTH a drain endpoint is
/// configured (Info.plist, Atlas hosts only) AND the user has explicitly
/// opted in via the Profile diagnostics toggle; either missing keeps it
/// local.
@MainActor
enum OnboardingFunnelTracker {
    private static let snapshotKey  = "onboarding.funnel.snapshot.v1"
    private static let sessionIDKey = "onboarding.funnel.sessionID.v1"
    private static let completedKey = "onboarding.funnel.completed.v1"

    /// Records the first time the user lands on a given step. Re-entries
    /// from a back-button are no-ops so the snapshot reflects the
    /// forward path, not noise from navigation experiments.
    static func recordStepEntered(_ stepName: String, index: Int) {
        var snapshot = currentSnapshot
        if snapshot.steps[stepName] != nil { return }
        snapshot.steps[stepName] = StepEntry(index: index, timestamp: Date())
        write(snapshot)
        AppLog.onboarding.info("step entered: \(stepName, privacy: .public) (\(index, privacy: .public))")
    }

    /// Hard cap on how many events the local snapshot retains. Older
    /// entries get dropped when the cap is exceeded so a user who
    /// resets onboarding many times doesn't accumulate an unbounded
    /// UserDefaults blob (audit security M-5). 200 is generous —
    /// the full v3 flow records ~25 events per run.
    private static let maxEvents = 200

    /// Records a free-form event for the current onboarding session. Used
    /// for things like "trial accepted", "trial declined", "creator code
    /// applied", "email captured" — moments that don't map to a step
    /// index but matter for funnel analysis. Event names are also
    /// truncated to 64 chars before logging to defend against a future
    /// caller passing user-controlled content.
    static func recordEvent(_ event: String) {
        let safeEvent = String(event.prefix(64))
        var snapshot = currentSnapshot
        snapshot.events.append(EventEntry(name: safeEvent, timestamp: Date()))
        if snapshot.events.count > maxEvents {
            snapshot.events.removeFirst(snapshot.events.count - maxEvents)
        }
        write(snapshot)
        // Log at .private so any future PII-bearing event doesn't leak
        // through Console / sysdiagnose. Step names stay .public —
        // they're not sensitive on their own.
        AppLog.onboarding.info("event: \(safeEvent, privacy: .private)")
    }

    /// Stamped on the terminal "Enter Atlas" tap. Locks the current
    /// snapshot under a UUID key so a future replay/upload job can drain
    /// completed runs without racing the in-flight one. Idempotent — a
    /// double-tap or two completion paths racing won't overwrite the
    /// first timestamp and won't duplicate the rows on drain (audit
    /// Onboarding P2).
    static func recordCompletion() {
        var snapshot = currentSnapshot
        guard snapshot.completedAt == nil else { return }
        snapshot.completedAt = Date()
        write(snapshot)
        UserDefaults.standard.set(true, forKey: completedKey)
        AppLog.onboarding.info("onboarding completed")
    }

    /// True after `recordCompletion()` has fired at least once. Surfaced
    /// for diagnostic settings screens that show "Funnel: complete" so a
    /// support engineer can confirm the user did finish the flow.
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Diagnostic accessor — returns the most recent snapshot decoded
    /// from UserDefaults. Returns an empty snapshot if nothing is
    /// stored or the stored payload fails to decode.
    static var snapshot: Snapshot { currentSnapshot }

    // MARK: - Drain

    /// Info.plist key holding the analytics drain endpoint. Absent
    /// entry / empty string disables the drain entirely. Configured
    /// per build by the operator so a TestFlight cohort can target a
    /// staging URL without baking it into App Store binaries.
    /// Must pass `DrainEndpoint` validation: HTTPS scheme AND an
    /// Atlas-controlled host — anything else is rejected.
    private static let endpointInfoKey = "OnboardingFunnelEndpoint"

    /// Info.plist key holding the optional rotatable drain secret,
    /// echoed as `X-Peptide-Proxy` so the analytics backend can
    /// reject anonymous POSTs.
    private static let secretInfoKey = "OnboardingFunnelSecret"

    /// Marks the most recent successful drain timestamp so a fast
    /// relaunch loop doesn't hammer the endpoint with the same
    /// snapshot. Resets when the snapshot is cleared after a drain.
    private static let drainedAtKey = "onboarding.funnel.drainedAt.v1"

    /// Explicit user opt-in for uploading the funnel snapshot.
    /// Defaults to false — without consent the drain is a no-op even
    /// when an endpoint is configured (audit 2.3). Internal so the
    /// Profile toggle can bind the same key via `@AppStorage`.
    static let consentKey = "onboarding.funnel.consent.v1"

    /// True when this build carries a valid drain endpoint. Gates the
    /// consent toggle in Profile so builds without an endpoint (all
    /// current ones) never show a sharing control that does nothing.
    static var drainConfigured: Bool { destinationURL != nil }

    static var sharingConsentGranted: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    /// Drains a completed onboarding snapshot to the configured
    /// endpoint, then resets the events array so a relaunch doesn't
    /// re-upload them. In-flight runs (those that haven't called
    /// `recordCompletion`) are left untouched so a crash mid-flow
    /// doesn't lose the partial trace.
    ///
    /// Fire-and-forget — failures are logged at `.warning` and do not
    /// surface to the user. The local snapshot stays on disk on
    /// failure so the next launch retries.
    static func drainIfReady() async {
        guard sharingConsentGranted else { return }
        let snap = currentSnapshot
        guard snap.completedAt != nil else { return }
        guard let url = destinationURL else { return }
        guard let payload = try? JSONEncoder().encode(snap) else {
            AppLog.onboarding.warning("funnel encode failed; skipping drain")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = DrainEndpoint.secret(infoKey: secretInfoKey) {
            request.setValue(secret, forHTTPHeaderField: DrainEndpoint.authHeaderField)
        }
        request.httpBody = payload
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                AppLog.onboarding.warning("funnel drain rejected by server")
                return
            }
            resetAfterDrain()
            UserDefaults.standard.set(Date(), forKey: drainedAtKey)
            AppLog.onboarding.info("funnel drained: \(snap.events.count, privacy: .public) events")
        } catch {
            AppLog.onboarding.warning("funnel drain failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static var destinationURL: URL? {
        DrainEndpoint.url(infoKey: endpointInfoKey)
    }

    /// Clears step + event arrays so a subsequent drain doesn't
    /// re-upload the same content, while preserving the sessionID
    /// and the `hasCompleted` flag — those gate the app's
    /// "show onboarding?" check and must survive the drain.
    private static func resetAfterDrain() {
        let fresh = Snapshot(
            sessionID: ensuredSessionID(),
            steps: [:],
            events: [],
            completedAt: nil
        )
        write(fresh)
    }

    // MARK: - Storage

    private static var currentSnapshot: Snapshot {
        if let data = UserDefaults.standard.data(forKey: snapshotKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return decoded
        }
        return Snapshot(sessionID: ensuredSessionID(), steps: [:], events: [], completedAt: nil)
    }

    private static func write(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    private static func ensuredSessionID() -> String {
        if let existing = UserDefaults.standard.string(forKey: sessionIDKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: sessionIDKey)
        return fresh
    }

    // MARK: - Snapshot

    struct Snapshot: Codable, Sendable {
        var sessionID: String
        var steps: [String: StepEntry]
        var events: [EventEntry]
        var completedAt: Date?
    }

    struct StepEntry: Codable, Sendable {
        let index: Int
        let timestamp: Date
    }

    struct EventEntry: Codable, Sendable {
        let name: String
        let timestamp: Date
    }
}
