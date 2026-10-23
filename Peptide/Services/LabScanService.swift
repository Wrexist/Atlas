import Foundation
import UIKit

/// Sends photos of a blood-test report to the proxy's `lab-scan` route
/// and decodes the transcribed markers. The transport — shared secret,
/// App Attest, retry, status mapping and the JPEG byte budget — is
/// `MealScannerService`'s; only the route and the decoding are new.
///
/// Report pages are health records. Nothing here logs their bytes or
/// the values read from them, and nothing is kept after the call.
final class LabScanService: Sendable {
    static let shared = LabScanService()

    /// Matches the route's page cap; one request, so one quota charge.
    static let maxPages = 4

    /// All pages share one request, and the proxy refuses bodies over
    /// 4.4 MB. Four typical pages fit; four very busy ones may not, and
    /// a clear error beats an upload that is refused at the end.
    static let maxEncodedBytes = 4_300_000

    private let transport: MealScannerService

    init(transport: MealScannerService = .shared) {
        self.transport = transport
    }

    enum LabScanError: Error, LocalizedError, Equatable {
        case notALabReport
        case nothingReadable
        case tooManyPages

        var errorDescription: String? {
            switch self {
            case .notALabReport:   String(localized: "That doesn't look like a lab report. Photograph the page with your results table.")
            case .nothingReadable: String(localized: "Couldn't read any results. Try a sharper photo with the whole table in frame.")
            case .tooManyPages:    String(localized: "Scan up to 4 pages at a time.")
            }
        }
    }

    func scan(pages: [UIImage]) async throws -> LabReportEngine.Scan {
        guard !pages.isEmpty, pages.count <= Self.maxPages else { throw LabScanError.tooManyPages }
        let images = try pages.map { try transport.uploadJPEG($0).base64EncodedString() }
        guard images.reduce(0, { $0 + $1.utf8.count }) <= Self.maxEncodedBytes else {
            throw MealScannerService.ScanError.imageTooLarge
        }
        let payload: [String: Any] = ["images": images, "locale": MealScannerService.localeIdentifier]
        let data = try await transport.post(payload, toSiblingRoute: "lab-scan")
        let scan: LabReportEngine.Scan
        do {
            scan = try LabReportEngine.decode(data)
        } catch {
            throw MealScannerService.ScanError.parseFailure
        }
        guard scan.isLabReport else { throw LabScanError.notALabReport }
        guard scan.markers.contains(where: { $0.value != nil }) else { throw LabScanError.nothingReadable }
        return scan
    }

    /// User-facing copy. The shared transport's errors talk about meals,
    /// so the ones a lab scan can hit are reworded here.
    static func message(for error: Error) -> String {
        switch error as? MealScannerService.ScanError {
        case .rateLimited?:
            return String(localized: "You've used a lot of AI scans recently. Wait a minute and try again — if you've hit today's limit, scanning resets tomorrow.")
        case .imageTooLarge?:
            return String(localized: "These pages are too large to upload together. Scan fewer pages at a time.")
        case .parseFailure?, .invalidResponse?, .implausibleResult?, .noFoodDetected?:
            return String(localized: "Couldn't read the results from the scanner. Try again, or enter the values by hand.")
        case .declined?:
            return String(localized: "The scanner couldn't analyze this report. Try a different photo.")
        case .routeMissing?:
            return String(localized: "Lab scanning isn't available on this server yet. Enter the values by hand for now.")
        case .serviceUnavailable?:
            return String(localized: "Lab scanning is temporarily unavailable. Try again later, or enter the values by hand.")
        case .offline?:
            return String(localized: "You're offline — lab scanning needs an internet connection. Reconnect and try again.")
        case .proxyNotConfigured?, .unauthorised?, .requestFailed?, .scanAllowanceSpent?:
            return error.localizedDescription
        case nil:
            return error.localizedDescription
        }
    }
}
