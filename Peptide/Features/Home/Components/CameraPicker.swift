import AVFoundation
import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around UIImagePickerController for camera capture.
/// PhotosPicker covers the photo library but cannot launch the camera, so the
/// profile customization sheet falls back to this for the "Take Photo" path.
///
/// Callers MUST resolve camera authorization through
/// `CameraAuthorization.resolve()` and only mount this view when the result
/// is `.granted`. `UIImagePickerController` with `sourceType = .camera`
/// silently presents a black live-view on `.denied` / `.restricted` with no
/// system prompt — the gate lives at the call site so the user gets a clear
/// "Open Settings" path instead of being trapped.
struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    let onCancel: () -> Void
    /// Front by default for the profile-photo flow. Meal scanning passes
    /// `.rear` so the camera opens facing the plate.
    var cameraDevice: UIImagePickerController.CameraDevice = .front
    /// `true` lets the user crop before confirming — fits the profile
    /// avatar flow. Meal scan opts out so capture is a single tap.
    var allowsEditing: Bool = true

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraDevice = cameraDevice
        controller.allowsEditing = allowsEditing
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(onPicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Prefer the user's edited (cropped) version when allowsEditing is on,
            // falling back to the raw original.
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true) { [weak self] in
                if let image {
                    self?.onPicked(image)
                } else {
                    self?.onCancel()
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.onCancel()
            }
        }
    }
}

extension UIImagePickerController.SourceType {
    /// True when the platform actually supports the requested source — used to
    /// hide the "Take Photo" action on simulators or devices without a camera.
    /// `isSourceTypeAvailable` is MainActor-isolated under Swift 6, so this
    /// accessor pins itself to the main actor.
    @MainActor
    static var cameraIsAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}

// MARK: - CameraAuthorization

/// Resolves the user's camera privacy authorization before any code path
/// presents `CameraPicker`. The four `AVAuthorizationStatus` cases need
/// different UX:
///
/// - `.authorized` → mount the picker.
/// - `.notDetermined` → request access; on grant, mount; on deny, fall
///   back to the photo library.
/// - `.denied` → user previously said no. Offer a deep-link to Settings.
/// - `.restricted` → parental controls. Settings link doesn't help here;
///   fall back to the photo library and explain why.
enum CameraAuthorization {
    enum Outcome {
        case granted
        case denied
        case restricted
    }

    /// Resolves the current authorization status, requesting access when
    /// the user hasn't yet decided. Safe to call from a button-tap handler
    /// — the `requestAccess` continuation is `@Sendable` and the
    /// `AVCaptureDevice` API is thread-agnostic.
    static func resolve() async -> Outcome {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .granted : .denied
        @unknown default:
            return .denied
        }
    }
}
