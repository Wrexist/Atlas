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
/// Caps stored records per kind to bound disk usage — 20 diagnostics,
/// 7 daily metrics — so a month of metric payloads can't push a crash
/// out. New records push out the oldest of their kind. Disk I/O runs
/// off the main actor, serialised so writes land in order.
@MainActor
@Observable
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber {

    static let shared = DiagnosticsService()

    /// Persistence file, in a Library directory marked excluded from
    /// iCloud backup — these are diagnostics, not user data.
    private let persistenceURL: URL

    /// In-memory cache of the most recent records, hot for the
    /// diagnostics UI. Bounded per kind by `Kind.storageCap`.
    private(set) var records: [Record] = []

    /// The latest queued load / save / delete. Each waits for the one
    /// before it, so a save never races the launch load or an older save.
    @ObservationIgnored private var pendingIO: Task<Void, Never>?

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

            var storageCap: Int {
                switch self {
                case .metric: 7
                case .diagnostic: 20
                }
            }
        }
    }

    // MARK: - Init

    private override init() {
        let manager = FileManager.default
        let libraryDir = manager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        var diagnosticsDir = libraryDir.appendingPathComponent("Diagnostics", isDirectory: true)
        // Best-effort create — if the dir already exists or the
        // disk is full, the write step below surfaces the failure
        // with a typed error.
        try? manager.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)
        var backupExclusion = URLResourceValues()
        backupExclusion.isExcludedFromBackup = true
        try? diagnosticsDir.setResourceValues(backupExclusion)
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

    /// Inserts a new record, evicts the oldest of its kind if over
    /// the cap, and queues the bounded list for disk. Public for tests.
    func ingest(payloadJSON: Data, kind: Record.Kind, receivedAt: Date) {
        let record = Record(
            id: UUID(),
            receivedAt: receivedAt,
            kind: kind,
            payloadJSON: payloadJSON
        )
        records = Self.capped([record] + records)
        enqueueIO { [persistenceURL] service in
            // Snapshot when the write runs, after any pending load merged.
            let snapshot = service.records
            await Task.detached(priority: .utility) {
                Self.write(snapshot, to: persistenceURL)
            }.value
        }
        AppLog.diagnostics.info(
            "Captured \(kind.rawValue, privacy: .public) payload, \(self.records.count, privacy: .public) total"
        )
    }

    /// Wipes the on-disk store and the in-memory cache. Used by
    /// the future diagnostics UI ("Clear all") and by tests.
    func reset() {
        records = []
        enqueueIO { [persistenceURL] service in
            service.records = []
            await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: persistenceURL)
            }.value
        }
    }

    /// Returns once every queued load, save and delete has finished.
    /// Public for tests.
    func settled() async {
        await pendingIO?.value
    }

    private func enqueueIO(_ operation: @escaping @MainActor @Sendable (DiagnosticsService) async -> Void) {
        let previous = pendingIO
        pendingIO = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func loadFromDisk() {
        enqueueIO { [persistenceURL] service in
            let loaded = await Task.detached(priority: .utility) {
                Self.read(from: persistenceURL)
            }.value
            // Anything ingested while the load ran is newer.
            service.records = Self.capped(service.records + loaded)
        }
    }

    private static func capped(_ records: [Record]) -> [Record] {
        var kept: [Record.Kind: Int] = [:]
        return records.filter { record in
            kept[record.kind, default: 0] += 1
            return kept[record.kind, default: 0] <= record.kind.storageCap
        }
    }

    private nonisolated static func write(_ records: [Record], to url: URL) {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.diagnostics.error(
                "Failed to save diagnostics records: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private nonisolated static func read(from url: URL) -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([Record].self, from: data)
        } catch {
            AppLog.diagnostics.error(
                "Failed to load diagnostics records, resetting: \(error.localizedDescription, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: url)
            return []
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
