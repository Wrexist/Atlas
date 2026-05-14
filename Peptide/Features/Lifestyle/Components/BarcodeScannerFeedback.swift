import UIKit
import AVFoundation

/// Single source of truth for the barcode-scan flow's haptic vocabulary.
/// Centralised so the feel stays consistent as the flow grows and so a
/// future "reduce haptics" preference only needs to flip one switch.
///
/// Each call is cheap — `UIFeedbackGenerator` instances allocate a
/// system resource on first use and Apple recommends not holding them
/// across UI events, so we construct per-call. Wrapping in
/// `@MainActor` because all UIKit feedback APIs require the main thread.
@MainActor
enum BarcodeHaptics {

    /// Subtle "I see something" the moment DataScanner locks on a
    /// barcode, before the lookup fires. Distinct from the lookup-
    /// result haptics so the user can feel the pipeline staging.
    static func detected() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Resolved a product against Open Food Facts.
    static func lookupSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Lookup failed (not found, network, decode). The .error
    /// notification is the right vocabulary — it's the standard
    /// "something didn't work" pattern users already recognize from
    /// iOS system flows.
    static func lookupFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Meal was successfully written to today's bucket. A heavier
    /// impact than `detected()` so the user feels the "commit"
    /// distinctly from the "scan" earlier in the flow.
    static func logCommitted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Undo invoked — `.warning` reads as "I'm undoing what I just
    /// did", less jarring than `.error` would be for a user-initiated
    /// action.
    static func logUndone() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        // Best-effort: a configuration-lock failure here means another
        // process owns the device. User can just tap again; no benefit
        // to logging or surfacing the error.
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
