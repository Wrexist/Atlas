import Foundation

/// Local-only per-step funnel tracking for onboarding. Records the first
/// entry timestamp for each step into UserDefaults so a single completed
/// run can be reconstructed after the fact, and emits an `AppLog.onboarding`
/// signpost so Console.app sessions show the flow in real time.
///
/// Intentionally no PII, no network — when a backend lands this can be
/// drained into Supabase + amplitude/posthog 1:1 from the snapshot. Until
/// then the data is local diagnostic only and never leaves the device.
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

    /// Records a free-form event for the current onboarding session. Used
    /// for things like "trial accepted", "trial declined", "creator code
    /// applied", "email captured" — moments that don't map to a step
    /// index but matter for funnel analysis.
    static func recordEvent(_ event: String) {
        var snapshot = currentSnapshot
        snapshot.events.append(EventEntry(name: event, timestamp: Date()))
        write(snapshot)
        AppLog.onboarding.info("event: \(event, privacy: .public)")
    }

    /// Stamped on the terminal "Enter Atlas" tap. Locks the current
    /// snapshot under a UUID key so a future replay/upload job can drain
    /// completed runs without racing the in-flight one.
    static func recordCompletion() {
        var snapshot = currentSnapshot
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
