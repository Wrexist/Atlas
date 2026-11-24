import CoreMotion
import SwiftUI

/// How far the phone has tipped from where it was held when a hero card
/// came on screen, for a small parallax tilt. Shared, reference-counted:
/// the sensor runs only while at least one view holds a lease, and reads
/// relative to the pose at start so a phone held at any angle rests flat.
@MainActor
@Observable
final class DeviceTilt {
    static let shared = DeviceTilt()

    /// Forward/back tip in radians, clamped to ±`limit`.
    private(set) var pitch: Double = 0
    /// Side-to-side tip in radians, clamped to ±`limit`.
    private(set) var roll: Double = 0

    /// Past ~14° the card would swing more than the eye follows.
    static let limit = 0.25
    /// Thirty reads a second is smooth through the spring that follows.
    private static let interval: TimeInterval = 1.0 / 30

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var leases = 0
    @ObservationIgnored private var reference: CMAttitude?

    private init() {}

    func start() {
        leases += 1
        guard leases == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = Self.interval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.read(motion.attitude) }
        }
    }

    func stop() {
        leases = max(0, leases - 1)
        guard leases == 0 else { return }
        manager.stopDeviceMotionUpdates()
        reference = nil
        pitch = 0
        roll = 0
    }

    private func read(_ attitude: CMAttitude) {
        guard let reference else {
            reference = attitude.copy() as? CMAttitude
            return
        }
        attitude.multiply(byInverseOf: reference)
        pitch = min(max(attitude.pitch, -Self.limit), Self.limit)
        roll = min(max(attitude.roll, -Self.limit), Self.limit)
    }
}

/// Lets a view float a few points over the surface under it: as the phone
/// tips, the view drifts the opposite way, the way a near object slides
/// across a far one. Runs only while the view is on screen, and never
/// under Reduce Motion or in screenshot captures, which need still frames.
private struct TiltParallax: ViewModifier {
    /// Points of drift at the tilt limit.
    let depth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = DeviceTilt.shared
    @State private var isOnScreen = true
    @State private var isShown = false
    @State private var leased = false

    private var isLive: Bool {
        isOnScreen && isShown && !reduceMotion && !ScreenshotMode.shared.isEnabled
    }

    func body(content: Content) -> some View {
        content
            .offset(
                x: isLive ? -tilt.roll / DeviceTilt.limit * depth : 0,
                y: isLive ? -tilt.pitch / DeviceTilt.limit * depth : 0
            )
            .appAnimation(AppAnimation.springSnappy, value: tilt.roll)
            .appAnimation(AppAnimation.springSnappy, value: tilt.pitch)
            .onScrollVisibilityChange { isOnScreen = $0 }
            .onAppear { isShown = true }
            .onDisappear {
                isShown = false
                lease(false)
            }
            .onChange(of: isLive, initial: true) { _, live in lease(live) }
    }

    private func lease(_ live: Bool) {
        guard live != leased else { return }
        leased = live
        live ? tilt.start() : tilt.stop()
    }
}

extension View {
    /// Floats the view `depth` points over its surface as the phone tips.
    func tiltParallax(depth: CGFloat) -> some View {
        modifier(TiltParallax(depth: depth))
    }
}
