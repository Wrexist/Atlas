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
    private static let limit = 0.25
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
