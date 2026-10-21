@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// The live rear camera that sits inside the table-scan sheet, rather
/// than a full-screen picker: the whole point of the shot is framing the
/// table, so the viewfinder stays where the cut-outs will appear.
///
/// Prefers the virtual multi-camera so "Table" can open on the
/// ultra-wide — the one lens that fits a whole table from a seat.
/// Callers resolve camera authorization first (`CameraAuthorization`).
@MainActor
final class TableCamera: NSObject, AVCapturePhotoCaptureDelegate {

    /// The three framings offered on the viewfinder.
    enum Lens: CaseIterable, Identifiable {
        case table, plate, dish
        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .table: "Table"
            case .plate: "Plate"
            case .dish:  "Dish"
            }
        }
    }

    static var isAvailable: Bool { device != nil }

    private static var device: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.peptidesai.app.table-camera")
    private var device: AVCaptureDevice?
    private var pending: CheckedContinuation<UIImage?, Never>?

    func start() {
        if device == nil { configure() }
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// The ultra-wide is zoom factor 1 on a virtual device; the main lens
    /// starts at its first switch-over factor.
    func frame(_ lens: Lens) {
        guard let device else { return }
        let main = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
        let factor: CGFloat = switch lens {
        case .table: 1
        case .plate: main
        case .dish:  main * 2
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {
            AppLog.diagnostics.error("Table camera zoom failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func capture() async -> UIImage? {
        guard pending == nil, session.isRunning else { return nil }
        return await withCheckedContinuation { continuation in
            pending = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func configure() {
        guard let device = Self.device, let input = try? AVCaptureDeviceInput(device: device) else { return }
        self.device = device
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        // Portrait, like every other photo the meal flows hand around.
        output.connection(with: .video)?.videoRotationAngle = 90
        session.commitConfiguration()
        frame(.table)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        Task { @MainActor in
            self.pending?.resume(returning: image)
            self.pending = nil
        }
    }
}

/// The viewfinder layer for a `TableCamera` session.
struct TableCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        view.previewLayer?.connection?.videoRotationAngle = 90
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.previewLayer?.connection?.videoRotationAngle = 90
    }
}
