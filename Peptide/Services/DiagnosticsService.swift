import Foundation
@preconcurrency import MetricKit

/// MetricKit subscriber that captures crash + hang + disk-write
/// diagnostic payloads delivered by iOS once per day (or right
/// after a crash on the next launch). Apple's TestFlight + App
/// Store Connect dashboards collect the same data on the server
/// side, but this gives the app — and a future backend — a local
/// copy that:
///
///   • lets a diagnostics screen in Profile show the developer
///     "yes, real users hit crash X" without leaving the device
///   • forms the foundation for future server upload (when the
///     backend lands) without re-instrumenting every crash path
///   • persists across launches so a crash signature on day 1 is
///     still visible when the user opens the app on day 14
///
/// Caps stored records at 20 to bound disk usage. New records push
/// out the oldest in FIFO order.
@MainActor
@Observable
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber {

    static let shared = DiagnosticsService()

    /// Persistence file. Lives under the app's Library so it's
    /// excluded from iCloud backup by default — these are
    /// diagnostics, not user data.
    private let persistenceURL: URL

    /// In-memory cache of the most recent records, hot for the
    /// diagnostics UI. Bounded by `maxStoredRecords`.
    private(set) var records: [Record] = []

    private static let maxStoredRecords = 20

    /// Records stored on disk. Carries a typed kind so the UI can
    /// label "Crash" vs "Hang" vs "Diagnostic" without re-parsing
    /// the payload JSON.
    struct Record: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let receivedAt: Date
        let kind: Kind
        /// Verbatim MetricKit payload JSON. Captured via
        /// `MXDiagnosticPayload.jsonRepresentation()` /
        /// `MXMetricPayload.jsonRepresentation()` so future server
        /// upload can deserialize without re-doing extraction work
        /// on every crash path.
        let payloadJSON: Data

        enum Kind: String, Codable, Sendable {
            case metric       // daily MXMetricPayload (perf, disk, energy)
            case diagnostic   // crash / hang / disk-write / cpu-exception
        }
    }

    // MARK: - Init

    private override init() {
        let manager = FileManager.default
        let libraryDir = manager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let diagnosticsDir = libraryDir.appendingPathComponent("Diagnostics", isDirectory: true)
        // Best-effort create — if the dir already exists or the
        // disk is full, the write step below surfaces the failure
        // with a typed error.
        try? manager.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)
        self.persistenceURL = diagnosticsDir.appendingPathComponent("records.json")
        super.init()
        loadFromDisk()
    }

    // MARK: - Subscription

    /// Call once on app launch to start receiving MetricKit
    /// payloads. Idempotent — subscribing twice with the same
    /// instance is a no-op as far as MetricKit is concerned.
    func startCollecting() {
        MXMetricManager.shared.add(self)
        AppLog.diagnostics.info("MetricKit subscription registered")
    }

    /// Symmetric stop. Tests use it to keep the global subscriber
    /// list clean across runs.
    func stopCollecting() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let captured = payloads.map { (Date(), $0.jsonRepresentation()) }
        Task { @MainActor in
            for (received, json) in captured {
                self.ingest(payloadJSON: json, kind: .metric, receivedAt: received)
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let captured = payloads.map { (Date(), $0.jsonRepresentation()) }
        Task { @MainActor in
            for (received, json) in captured {
                self.ingest(payloadJSON: json, kind: .diagnostic, receivedAt: received)
            }
        }
    }

    // MARK: - Persistence

    /// Inserts a new record, evicts the oldest if over the cap,
    /// and writes the bounded list to disk. Public for tests.
    func ingest(payloadJSON: Data, kind: Record.Kind, receivedAt: Date) {
        let record = Record(
            id: UUID(),
            receivedAt: receivedAt,
            kind: kind,
            payloadJSON: payloadJSON
        )
        records.insert(record, at: 0)
        if records.count > Self.maxStoredRecords {
            records.removeLast(records.count - Self.maxStoredRecords)
        }
        saveToDisk()
        AppLog.diagnostics.info(
            "Captured \(kind.rawValue, privacy: .public) payload, \(self.records.count, privacy: .public) total"
        )
    }

    /// Wipes the on-disk store and the in-memory cache. Used by
    /// the future diagnostics UI ("Clear all") and by tests.
    func reset() {
        records = []
        try? FileManager.default.removeItem(at: persistenceURL)
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            AppLog.diagnostics.error(
                "Failed to save diagnostics records: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: persistenceURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([Record].self, from: data)
            records = decoded
        } catch {
            AppLog.diagnostics.error(
                "Failed to load diagnostics records, resetting: \(error.localizedDescription, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: persistenceURL)
        }
    }

    // MARK: - Test seam

    /// Test-only init that points at a caller-provided URL so unit
    /// tests don't share the singleton's Library/Diagnostics dir.
    /// Not exposed via .shared.
    init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        super.init()
        loadFromDisk()
    }
}
