@preconcurrency import AVFoundation

/// Names the barcode-scan flow's haptic vocabulary so the feel stays
/// consistent as the flow grows. The actual firing delegates to
/// `Haptics`, which honours the global "Haptic feedback" setting in one
/// place — so the "reduce haptics" preference these calls used to need
/// a manual guard for is now respected automatically.
@MainActor
enum BarcodeHaptics {

    /// Subtle "I see something" the moment DataScanner locks on a
    /// barcode, before the lookup fires. Distinct from the lookup-
    /// result haptics so the user can feel the pipeline staging.
    static func detected() {
        Haptics.impact(.light)
    }

    /// Resolved a product against Open Food Facts.
    static func lookupSuccess() {
        Haptics.success()
    }

    /// Lookup failed (not found, network, decode). The .error
    /// notification is the right vocabulary — it's the standard
    /// "something didn't work" pattern users already recognize from
    /// iOS system flows.
    static func lookupFailure() {
        Haptics.error()
    }

    /// Meal was successfully written to today's bucket. A heavier
    /// impact than `detected()` so the user feels the "commit"
    /// distinctly from the "scan" earlier in the flow. One pulse only:
    /// stacking it on a `.success` notification blurs both into mush.
    static func logCommitted() {
        Haptics.impact(.medium)
    }

    /// Undo invoked — `.warning` reads as "I'm undoing what I just
    /// did", less jarring than `.error` would be for a user-initiated
    /// action.
    static func logUndone() {
        Haptics.warning()
    }
}

/// Wraps the device's torch (flashlight) so the scanner UI can offer a
/// toggle for low-light scans. DataScanner uses the default video
/// device under the hood, which is the same one we reach for here, so
/// turning the torch on through this helper lights up the camera the
/// scanner is already streaming from.
///
/// Best-effort: silently no-ops on simulator, devices without a torch
/// (older iPads), or when the device is locked by another configuration.
@MainActor
enum BarcodeTorch {

    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch == true
    }

    static var isOn: Bool {
        AVCaptureDevice.default(for: .video)?.torchMode == .on
    }

    static func set(_ on: Bool) {
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.isTorchModeSupported(mode) else { return }
        // Best-effort: a configuration-lock failure means another process
        // owns the device, and setting torchMode without the lock raises.
        // The user can just tap again.
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        device.torchMode = mode
    }
}
