@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Meal camera for iPhones with a LiDAR sensor. Takes the same photo the
/// system camera would, plus one depth reading of the food, so the
/// scanner gets a real scale (`PhotoScale`) to size portions from.
///
/// Callers resolve camera authorization first, exactly as for
/// `CameraPicker`, and fall back to it where `isAvailable` is false.
struct DepthMealCamera: UIViewControllerRepresentable {
    let onPicked: (UIImage, PhotoScale?) -> Void
    let onCancel: () -> Void

    @MainActor
    static var isAvailable: Bool { DepthCameraController.lidarDevice != nil }

    func makeUIViewController(context: Context) -> DepthCameraController {
        let controller = DepthCameraController()
        controller.onPicked = onPicked
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_: DepthCameraController, context _: Context) {}
}

final class DepthCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onPicked: ((UIImage, PhotoScale?) -> Void)?
    var onCancel: (() -> Void)?

    static var lidarDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
    }

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let preview = AVCaptureVideoPreviewLayer()
    private let sessionQueue = DispatchQueue(label: "com.peptidesai.app.depth-camera")
    private var fieldOfView: Double?
    private let shutter = UIButton(type: .custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        configureSession()
        addControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self, session] in
            session.startRunning()
            Task { @MainActor in self?.refreshShutter() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in session.stopRunning() }
    }

    private func configureSession() {
        guard let device = Self.lidarDevice, let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.isDepthDataDeliveryEnabled = output.isDepthDataDeliverySupported
        // Portrait, like the system camera the rest of the flow expects.
        output.connection(with: .video)?.videoRotationAngle = 90
        session.commitConfiguration()
        preview.connection?.videoRotationAngle = 90
        fieldOfView = Double(device.activeFormat.videoFieldOfView)
    }

    private func addControls() {
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.isEnabled = false
        shutter.backgroundColor = .white
        shutter.layer.cornerRadius = 36
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        shutter.accessibilityLabel = String(localized: "Take photo")
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle(String(localized: "Cancel"), for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancel.titleLabel?.adjustsFontForContentSizeCategory = true
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        view.addSubview(shutter)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72),
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancel.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    /// `capturePhoto` raises an exception without an active video
    /// connection: before the session starts, while it is interrupted, or
    /// when the LiDAR input couldn't be added at all.
    private var canCapture: Bool {
        guard session.isRunning, !session.isInterrupted,
              let connection = output.connection(with: .video) else { return false }
        return connection.isActive && connection.isEnabled
    }

    private func refreshShutter() {
        shutter.isEnabled = canCapture
    }

    @objc private func capture() {
        guard canCapture else {
            refreshShutter()
            return
        }
        shutter.isEnabled = false
        let settings = AVCapturePhotoSettings()
        settings.isDepthDataDeliveryEnabled = output.isDepthDataDeliveryEnabled
        output.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        let distance = photo.depthData.flatMap(Self.centreDistance(of:))
        Task { @MainActor in
            guard let image else {
                self.refreshShutter()
                return
            }
            var scale: PhotoScale?
            if let distance, let fov = self.fieldOfView {
                scale = PhotoScale(distanceMeters: distance, longEdgeFOVDegrees: fov, aspect: 0.75)
            }
            self.onPicked?(image, scale)
        }
    }

    /// The food sits in the middle of a meal photo, so only the centre
    /// third of the depth map is read.
    nonisolated private static func centreDistance(of depthData: AVDepthData) -> Double? {
        let map = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var depths: [Float] = []
        for y in (height / 3)..<(2 * height / 3) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in (width / 3)..<(2 * width / 3) { depths.append(row[x]) }
        }
        return PhotoScale.medianDistance(depths)
    }
}
