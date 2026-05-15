import SwiftUI
import VisionKit
@preconcurrency import AVFoundation

/// Live barcode-capture surface wrapping `DataScannerViewController`.
///
/// `DataScannerViewController` is iOS 16+ but requires an A12 Bionic or
/// later, so callers must check `BarcodeScannerView.canScan` before
/// presenting. The simulator and older devices fall back to manual
/// entry in `BarcodeScanFlow`, so this view never has to render an
/// "unsupported" empty state itself.
struct BarcodeScannerView: UIViewControllerRepresentable {

    /// Fires once per stable barcode read. The flow pauses scanning by
    /// dismissing the view, so callers don't have to debounce.
    let onDetected: (String) -> Void

    /// Fired when the system reports a configuration or permission
    /// failure that can't be self-recovered (e.g. camera denied).
    let onError: (String) -> Void

    /// True when the current device + OS combo can run DataScanner.
    /// The flow checks this before presenting so the user never lands
    /// on a broken camera surface.
    static var canScan: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        // updateUIViewController fires on every parent re-render. Calling
        // startScanning while already running throws ScanningUnavailable,
        // so guard on isScanning to keep the AVCaptureSession steady
        // through unrelated state churn.
        guard !controller.isScanning else { return }
        do {
            try controller.startScanning()
        } catch {
            onError(error.localizedDescription)
        }
    }

    static func dismantleUIViewController(
        _ controller: DataScannerViewController,
        coordinator: Coordinator
    ) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetected: onDetected)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onDetected: (String) -> Void
        private var fired = false

        init(onDetected: @escaping (String) -> Void) {
            self.onDetected = onDetected
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            // First-stable-read wins — the parent state machine takes
            // it from here, so we ignore subsequent detections to
            // avoid double-firing while the controller tears down.
            guard !fired, let payload = Self.firstBarcodePayload(in: addedItems) else { return }
            fired = true
            dataScanner.stopScanning()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDetected(payload)
        }

        private static func firstBarcodePayload(in items: [RecognizedItem]) -> String? {
            for item in items {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    return payload
                }
            }
            return nil
        }
    }
}

/// Standalone camera-permission probe so the flow can prompt without
/// instantiating the scanner. Mirrors `AVCaptureDevice.requestAccess`
/// in async form to keep the call site readable.
enum BarcodeCameraAuthorization {

    static var current: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests camera access if the user hasn't decided yet. Returns
    /// the post-request status so the caller can branch once.
    static func request() async -> AVAuthorizationStatus {
        if current == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return current
    }
}
