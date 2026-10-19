import Foundation

/// Real-world scale for a meal photo, from the LiDAR sensor: how far the
/// food was from the lens and what the camera's field of view covers at
/// that distance. Lets the scanner size portions from centimetres
/// instead of guessing from an assumed plate diameter.
struct PhotoScale: Equatable, Sendable {
    let distanceMeters: Double
    /// Field of view across the photo's long edge.
    let longEdgeFOVDegrees: Double
    /// Short edge over long edge, 0.75 for a 4:3 photo.
    let aspect: Double

    var longEdgeCm: Double { 2 * distanceMeters * tan(longEdgeFOVDegrees * .pi / 360) * 100 }
    var shortEdgeCm: Double { longEdgeCm * aspect }

    /// What the scanner is told alongside the photo.
    var hint: String {
        "Measured by the phone's LiDAR: the food is about \(Int((distanceMeters * 100).rounded())) cm from the camera, "
            + "so the photo spans roughly \(Int(longEdgeCm.rounded())) × \(Int(shortEdgeCm.rounded())) cm "
            + "(long × short edge). Use this as the scale for portion sizes instead of assuming a plate size."
    }

    /// LiDAR reads well from about 10 cm to a few metres; a meal photo
    /// is taken from 15–80 cm.
    static let usableDepth: ClosedRange<Float> = 0.1...2.0

    /// Median of the usable readings, robust against the edge of the
    /// table or a hand at the frame's border. Nil when too few readings
    /// are usable to trust.
    static func medianDistance(_ depths: [Float]) -> Double? {
        let usable = depths.filter { $0.isFinite && usableDepth.contains($0) }.sorted()
        guard usable.count >= 20 else { return nil }
        return Double(usable[usable.count / 2])
    }
}
