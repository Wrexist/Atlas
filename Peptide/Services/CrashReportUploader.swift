import Foundation

/// Sends MetricKit crash, hang and resource diagnostics to the Atlas
/// proxy so they reach the developer, without a crash-reporting SDK.
/// Each payload is trimmed here to app / OS version, device model,
/// the exception and the call stack MetricKit captured — no user
/// identifier, no health data.
///
/// On by default; Settings → "Share crash reports" turns it off.
/// Fire-and-forget: one attempt, dropped on any failure.
enum CrashReportUploader {
    static let enabledKey = "shareCrashReports"

    /// Under the proxy's 256 KB cap, with room for JSON re-encoding.
    private static let maxBodyBytes = 200 * 1024
    private static let maxDiagnostics = 10

    private static let sections: [(key: String, type: String)] = [
        ("crashDiagnostics", "crash"),
        ("hangDiagnostics", "hang"),
        ("cpuExceptionDiagnostics", "cpu_exception"),
        ("diskWriteExceptionDiagnostics", "disk_write_exception"),
        ("appLaunchDiagnostics", "app_launch"),
    ]

    private static let metaDataKeys: Set<String> = [
        "appVersion", "appBuildVersion", "osVersion", "deviceType", "platformArchitecture",
        "bundleIdentifier", "isTestFlightApp", "lowPowerModeEnabled", "exceptionType",
        "exceptionCode", "signal", "terminationReason", "virtualMemoryRegionInfo",
        "hangDuration", "totalCPUTime", "totalSampledTime", "writesCaused", "launchDuration",
    ]

    /// MetricKit's key for an uncaught Objective-C exception has varied
    /// between OS versions; either is forwarded as `exceptionReason`.
    private static let exceptionReasonSourceKeys = ["exceptionReason", "objectiveCexceptionReason"]

    /// The exception's composed message and arguments can quote app data,
    /// so only its name, class and format string leave the device.
    private static let exceptionReasonKeys: Set<String> = ["exceptionName", "className", "formatString"]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Posts one `MXDiagnosticPayload.jsonRepresentation()`. Safe from
    /// any thread; returns immediately.
    static func send(diagnosticPayloadJSON json: Data) {
        guard isEnabled,
              let url = endpoint,
              let secret = MealScannerService.stringSetting(forKey: "MEAL_SCANNER_SECRET"),
              let body = body(fromDiagnosticJSON: json)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Peptide-Proxy")
        request.httpBody = body
        Task.detached(priority: .background) { [request] in
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// A sibling route of the meal scanner on the same proxy, sharing its
    /// secret, so a build needs no extra setting.
    private static var endpoint: URL? {
        MealScannerService.urlSetting(forKey: "MEAL_SCANNER_ENDPOINT")?
            .deletingLastPathComponent()
            .appendingPathComponent("crash-report")
    }

    // MARK: - Payload

    /// The upload body for one diagnostic payload, or nil when it holds
    /// no diagnostic. Call stacks are dropped if the body would exceed
    /// the size cap. Internal for tests.
    static func body(fromDiagnosticJSON json: Data) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let diagnostics: [[String: Any]] = sections.flatMap { section in
            (root[section.key] as? [[String: Any]] ?? []).map { trimmed($0, type: section.type) }
        }
        guard !diagnostics.isEmpty else { return nil }
        let kept = Array(diagnostics.prefix(maxDiagnostics))
        let withoutStacks = kept.map { diagnostic in diagnostic.filter { $0.key != "callStackTree" } }
        return encoded(kept, root: root) ?? encoded(withoutStacks, root: root)
    }

    private static func encoded(_ diagnostics: [[String: Any]], root: [String: Any]) -> Data? {
        var body: [String: Any] = ["schema": 1, "diagnostics": diagnostics]
        body["appBinary"] = Bundle.main.executableURL?.lastPathComponent
        body["timeStampBegin"] = root["timeStampBegin"]
        body["timeStampEnd"] = root["timeStampEnd"]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              data.count <= maxBodyBytes
        else { return nil }
        return data
    }

    private static func trimmed(_ diagnostic: [String: Any], type: String) -> [String: Any] {
        let source = diagnostic["diagnosticMetaData"] as? [String: Any] ?? [:]
        var metaData = source.filter { metaDataKeys.contains($0.key) }
        let reason = exceptionReasonSourceKeys.lazy.compactMap { source[$0] as? [String: Any] }.first
        if let reason {
            metaData["exceptionReason"] = reason.filter { exceptionReasonKeys.contains($0.key) }
        }
        var result: [String: Any] = ["type": type, "metaData": metaData]
        result["callStackTree"] = attributedStacks(diagnostic["callStackTree"])
        return result
    }

    /// Keeps only the thread MetricKit attributes the problem to (the one
    /// that crashed or hung) when it marks one: the other threads are most
    /// of a crash payload's size and little of its signal.
    private static func attributedStacks(_ tree: Any?) -> Any? {
        guard var stackTree = tree as? [String: Any],
              let stacks = stackTree["callStacks"] as? [[String: Any]]
        else { return tree }
        let attributed = stacks.filter { $0["threadAttributed"] as? Bool == true }
        if !attributed.isEmpty { stackTree["callStacks"] = attributed }
        return stackTree
    }
}
