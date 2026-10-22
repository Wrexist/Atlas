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
    /// Keeps the photo upright however the phone is held — a long table
    /// is often shot in landscape.
    private var rotation: AVCaptureDevice.RotationCoordinator?
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

    /// Turns a viewfinder layer upright for the way the screen is held.
    func previewRotation(for layer: AVCaptureVideoPreviewLayer) -> AVCaptureDevice.RotationCoordinator? {
        device.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: layer) }
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
            if let rotation, let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotation.videoRotationAngleForHorizonLevelCapture) {
                connection.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelCapture
            }
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
        session.commitConfiguration()
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
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
    let camera: TableCamera

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
        var rotation: AVCaptureDevice.RotationCoordinator?

        /// Turning the phone re-lays the view out, so the viewfinder is
        /// turned upright here.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let rotation, let connection = previewLayer?.connection,
                  connection.isVideoRotationAngleSupported(rotation.videoRotationAngleForHorizonLevelPreview) else { return }
            connection.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelPreview
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer?.session = camera.session
        view.previewLayer?.videoGravity = .resizeAspectFill
        if let layer = view.previewLayer { view.rotation = camera.previewRotation(for: layer) }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.setNeedsLayout()
    }
}
