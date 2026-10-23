import XCTest
@testable import Peptide

/// The upload body is the privacy boundary for crash reports: only the
/// allow-listed metadata and the attributed thread's stack may leave the
/// device. MetricKit payloads can't be faked through its API, so these
/// feed the body builder the JSON shape `jsonRepresentation()` produces.
final class CrashReportUploaderTests: XCTestCase {

    private func payload(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root)
    }

    private func decodedBody(_ root: [String: Any]) throws -> [String: Any] {
        let body = try XCTUnwrap(CrashReportUploader.body(fromDiagnosticJSON: payload(root)))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func crash(metaData extra: [String: Any] = [:]) -> [String: Any] {
        var metaData: [String: Any] = [
            "appVersion": "1.3.0",
            "appBuildVersion": "140",
            "osVersion": "iPhone OS 18.2 (22C152)",
            "deviceType": "iPhone16,1",
            "signal": 11,
            "pid": 4242,
            "regionFormat": "SE",
        ]
        metaData.merge(extra) { _, new in new }
        let otherThread: [String: Any] = ["threadAttributed": false, "callStackRootFrames": [["address": 1]]]
        let crashedThread: [String: Any] = ["threadAttributed": true, "callStackRootFrames": [["address": 2]]]
        let tree: [String: Any] = ["callStackPerThread": true, "callStacks": [otherThread, crashedThread]]
        return ["diagnosticMetaData": metaData, "callStackTree": tree]
    }

    func test_crashPayload_keepsAllowListedMetadataOnly() throws {
        let body = try decodedBody(["crashDiagnostics": [crash()]])
        let diagnostic = try XCTUnwrap((body["diagnostics"] as? [[String: Any]])?.first)
        let metaData = try XCTUnwrap(diagnostic["metaData"] as? [String: Any])

        XCTAssertEqual(body["schema"] as? Int, 1)
        XCTAssertEqual(diagnostic["type"] as? String, "crash")
        XCTAssertEqual(metaData["appVersion"] as? String, "1.3.0")
        XCTAssertEqual(metaData["signal"] as? Int, 11)
        XCTAssertNil(metaData["pid"])
        XCTAssertNil(metaData["regionFormat"])
    }

    func test_crashPayload_keepsOnlyTheAttributedThread() throws {
        let body = try decodedBody(["crashDiagnostics": [crash()]])
        let diagnostic = try XCTUnwrap((body["diagnostics"] as? [[String: Any]])?.first)
        let tree = try XCTUnwrap(diagnostic["callStackTree"] as? [String: Any])
        let stacks = try XCTUnwrap(tree["callStacks"] as? [[String: Any]])

        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks.first?["threadAttributed"] as? Bool, true)
    }

    func test_exceptionReason_dropsTheComposedMessage() throws {
        let reason: [String: Any] = [
            "exceptionName": "NSInvalidArgumentException",
            "composedMessage": "value 'private' is invalid",
            "arguments": ["private"],
        ]
        let body = try decodedBody(["crashDiagnostics": [crash(metaData: ["objectiveCexceptionReason": reason])]])
        let diagnostic = try XCTUnwrap((body["diagnostics"] as? [[String: Any]])?.first)
        let metaData = try XCTUnwrap(diagnostic["metaData"] as? [String: Any])
        let forwarded = try XCTUnwrap(metaData["exceptionReason"] as? [String: Any])

        XCTAssertEqual(forwarded["exceptionName"] as? String, "NSInvalidArgumentException")
        XCTAssertNil(forwarded["composedMessage"])
        XCTAssertNil(forwarded["arguments"])
    }

    func test_everyDiagnosticSection_isTypedForTheProxy() throws {
        let empty: [String: Any] = ["diagnosticMetaData": [String: Any]()]
        let body = try decodedBody([
            "hangDiagnostics": [["diagnosticMetaData": ["hangDuration": "3 sec"]]],
            "cpuExceptionDiagnostics": [empty],
            "diskWriteExceptionDiagnostics": [empty],
        ])
        let types = (body["diagnostics"] as? [[String: Any]])?.compactMap { $0["type"] as? String }

        XCTAssertEqual(types, ["hang", "cpu_exception", "disk_write_exception"])
    }

    func test_payloadWithoutDiagnostics_sendsNothing() throws {
        let empty = try payload(["timeStampEnd": "2026-10-20 08:00:00 +0000"])
        XCTAssertNil(CrashReportUploader.body(fromDiagnosticJSON: empty))
        XCTAssertNil(CrashReportUploader.body(fromDiagnosticJSON: Data("not json".utf8)))
    }

    func test_oversizedStacks_areDroppedButTheReportStillGoes() throws {
        let frames = (0..<20_000).map { ["address": $0, "binaryName": "Peptide"] as [String: Any] }
        var huge = crash()
        let thread: [String: Any] = ["threadAttributed": true, "callStackRootFrames": frames]
        huge["callStackTree"] = ["callStacks": [thread]]

        let body = try decodedBody(["crashDiagnostics": [huge]])
        let diagnostic = try XCTUnwrap((body["diagnostics"] as? [[String: Any]])?.first)

        XCTAssertNil(diagnostic["callStackTree"])
        XCTAssertEqual(diagnostic["type"] as? String, "crash")
    }
}
