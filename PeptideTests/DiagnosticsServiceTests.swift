import XCTest
@testable import Peptide

/// The MetricKit subscription side is hard to mock (no public API
/// to fire a fake `MXDiagnosticPayload`), but the persistence layer
/// — ingest, cap, FIFO eviction, save/load round-trip, reset — is
/// pure data plumbing and where bugs would actually hide. Lock it
/// down here.
@MainActor
final class DiagnosticsServiceTests: XCTestCase {

    private var tempURL: URL!
    private var service: DiagnosticsService!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsTests-\(UUID().uuidString).json")
        service = DiagnosticsService(persistenceURL: tempURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        service = nil
        try await super.tearDown()
    }

    // MARK: - Ingest + bound

    func test_ingest_addsRecordToTop() {
        let json = Data(#"{"kind":"crash"}"#.utf8)
        service.ingest(payloadJSON: json, kind: .diagnostic, receivedAt: Date())
        XCTAssertEqual(service.records.count, 1)
        XCTAssertEqual(service.records[0].kind, .diagnostic)
        XCTAssertEqual(service.records[0].payloadJSON, json)
    }

    func test_ingest_insertsNewestFirst() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later   = earlier.addingTimeInterval(3600)
        service.ingest(payloadJSON: Data("a".utf8), kind: .metric,     receivedAt: earlier)
        service.ingest(payloadJSON: Data("b".utf8), kind: .diagnostic, receivedAt: later)
        XCTAssertEqual(service.records[0].payloadJSON, Data("b".utf8))
        XCTAssertEqual(service.records[1].payloadJSON, Data("a".utf8))
    }

    /// 20-record cap with FIFO eviction. Inserting a 21st pushes
    /// the oldest out and the cap holds. The bound exists so a
    /// long-running install can't grow the diagnostics file
    /// unbounded.
    func test_ingest_evictsOldestWhenOverCap() {
        for i in 0..<25 {
            service.ingest(
                payloadJSON: Data("\(i)".utf8),
                kind: .metric,
                receivedAt: Date(timeIntervalSince1970: TimeInterval(i))
            )
        }
        XCTAssertEqual(service.records.count, 20)
        // Newest first → index 0 is "24", oldest kept is "5"
        // (records 0…4 were evicted).
        XCTAssertEqual(service.records.first?.payloadJSON, Data("24".utf8))
        XCTAssertEqual(service.records.last?.payloadJSON,  Data("5".utf8))
    }

    // MARK: - Disk round-trip

    func test_ingest_persistsAcrossInstances() {
        let json = Data(#"{"x":1}"#.utf8)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        service.ingest(payloadJSON: json, kind: .diagnostic, receivedAt: when)

        // Spin up a second service against the same URL — simulates
        // app relaunch.
        let reloaded = DiagnosticsService(persistenceURL: tempURL)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records[0].payloadJSON, json)
        XCTAssertEqual(reloaded.records[0].kind, .diagnostic)
        // Date precision rounds to ms when JSON-encoded; compare
        // with millisecond tolerance.
        XCTAssertEqual(
            reloaded.records[0].receivedAt.timeIntervalSince1970,
            when.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    /// A corrupt records file must not crash the service — it
    /// should silently reset. This guards against a partial-write
    /// scenario on a bad shutdown.
    func test_loadFromDisk_corruptFile_resetsCleanly() throws {
        try Data("this is not JSON".utf8).write(to: tempURL)
        let reloaded = DiagnosticsService(persistenceURL: tempURL)
        XCTAssertTrue(reloaded.records.isEmpty)
    }

    // MARK: - Reset

    func test_reset_clearsInMemoryAndDisk() {
        service.ingest(payloadJSON: Data("a".utf8), kind: .metric, receivedAt: Date())
        XCTAssertEqual(service.records.count, 1)

        service.reset()
        XCTAssertTrue(service.records.isEmpty)

        // Second instance on the same URL must also start empty.
        let reloaded = DiagnosticsService(persistenceURL: tempURL)
        XCTAssertTrue(reloaded.records.isEmpty)
    }
}
