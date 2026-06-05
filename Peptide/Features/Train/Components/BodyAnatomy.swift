import SwiftUI

/// Geometric definitions for the anatomical figure used by
/// `MuscleMapView`. Everything is drawn in a normalized
/// `[0…1] × [0…2.4]` coordinate space (1.0 wide, 2.4 tall — the
/// roughly 8-head canonical figure ratio). The view scales these up
/// to fit whatever pixel rect it receives through `GeometryReader`.
///
/// Every muscle *head* is its own region, authored as a short list of
/// perimeter points run through `smoothClosed` (a closed Catmull-Rom
/// spline) so the shapes read as organic anatomy — three deltoid heads,
/// the clavicular/sternal pec, the three quad heads, the long/lateral
/// triceps, the gastrocnemius heads and soleus. Bilateral muscles are
/// drawn from one side through `mirror`, so the figure stays perfectly
/// symmetric. A faint `skeleton` layer grounds it as an anatomy chart.
///
/// Keeping the geometry in one place means the muscle map can be
/// re-skinned (stroke weights, palette, eventually commissioned asset
/// packs) without touching the view layer.
enum BodyAnatomy {

    /// Canonical aspect ratio of a single body figure (width / height).
    static let aspect: CGFloat = 1.0 / 2.4

    /// Reflects a point across the vertical mid-line (x → 1 − x).
    static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)

    // MARK: - Silhouette

    /// Right-half perimeter, crown → crotch, traced down the outside of a
    /// broad-shouldered, V-tapered athletic figure. The left half is the
    /// mirror of these points, so the outline is exactly symmetric.
    private static let rightHalf: [CGPoint] = [
        CGPoint(x: 0.500, y: 0.045), CGPoint(x: 0.598, y: 0.135), CGPoint(x: 0.585, y: 0.238),
        CGPoint(x: 0.545, y: 0.300), CGPoint(x: 0.540, y: 0.356), CGPoint(x: 0.616, y: 0.392),
        CGPoint(x: 0.726, y: 0.416), CGPoint(x: 0.850, y: 0.476), CGPoint(x: 0.878, y: 0.620),
        CGPoint(x: 0.868, y: 0.762), CGPoint(x: 0.848, y: 0.965), CGPoint(x: 0.866, y: 1.075),
        CGPoint(x: 0.820, y: 1.300), CGPoint(x: 0.814, y: 1.374), CGPoint(x: 0.762, y: 1.374),
        CGPoint(x: 0.756, y: 1.298), CGPoint(x: 0.726, y: 1.040), CGPoint(x: 0.704, y: 0.962),
        CGPoint(x: 0.662, y: 0.586), CGPoint(x: 0.640, y: 0.842), CGPoint(x: 0.626, y: 1.046),
        CGPoint(x: 0.694, y: 1.300), CGPoint(x: 0.706, y: 1.472), CGPoint(x: 0.636, y: 1.860),
        CGPoint(x: 0.648, y: 2.022), CGPoint(x: 0.582, y: 2.252), CGPoint(x: 0.556, y: 2.306),
        CGPoint(x: 0.602, y: 2.366), CGPoint(x: 0.516, y: 2.366), CGPoint(x: 0.512, y: 2.308),
        CGPoint(x: 0.512, y: 1.890), CGPoint(x: 0.506, y: 1.760), CGPoint(x: 0.500, y: 1.430),
    ]

    static func frontSilhouette() -> Path {
        var pts = rightHalf
        pts += rightHalf.dropFirst().dropLast().reversed().map {
            CGPoint(x: 1 - $0.x, y: $0.y)
        }
        return smoothClosed(pts)
    }

    /// The back outline matches the front; the back-only muscle + skeleton
    /// layers convey the difference in view.
    static func backSilhouette() -> Path { frontSilhouette() }

    // MARK: - Front heads

    static func pecSternal() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.495, y: 0.470), CGPoint(x: 0.392, y: 0.474), CGPoint(x: 0.318, y: 0.500),
        CGPoint(x: 0.300, y: 0.566), CGPoint(x: 0.336, y: 0.636), CGPoint(x: 0.430, y: 0.654),
        CGPoint(x: 0.495, y: 0.624),
    ])) }

    static func pecClavicular() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.495, y: 0.450), CGPoint(x: 0.398, y: 0.450), CGPoint(x: 0.336, y: 0.470),
        CGPoint(x: 0.352, y: 0.514), CGPoint(x: 0.440, y: 0.520), CGPoint(x: 0.495, y: 0.500),
    ])) }

    static func deltAnterior() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.250, y: 0.452), CGPoint(x: 0.300, y: 0.470), CGPoint(x: 0.300, y: 0.522),
        CGPoint(x: 0.262, y: 0.584), CGPoint(x: 0.224, y: 0.560), CGPoint(x: 0.232, y: 0.498),
    ])) }

    /// Lateral deltoid cap — the same head is visible from front and back;
    /// `deltLateralFront`/`deltLateralBack` share this geometry.
    private static func deltLateralCap() -> Path { smoothClosed([
        CGPoint(x: 0.150, y: 0.466), CGPoint(x: 0.198, y: 0.410), CGPoint(x: 0.254, y: 0.454),
        CGPoint(x: 0.238, y: 0.522), CGPoint(x: 0.180, y: 0.530),
    ]) }
    static func deltLateralFront() -> Path { mirrorPair(deltLateralCap()) }
    static func deltLateralBack() -> Path { mirrorPair(deltLateralCap()) }

    static func deltPosterior() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.150, y: 0.470), CGPoint(x: 0.182, y: 0.524), CGPoint(x: 0.216, y: 0.558),
        CGPoint(x: 0.198, y: 0.612), CGPoint(x: 0.150, y: 0.574), CGPoint(x: 0.142, y: 0.514),
    ])) }

    static func biceps() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.205, y: 0.500), CGPoint(x: 0.256, y: 0.606), CGPoint(x: 0.232, y: 0.730),
        CGPoint(x: 0.172, y: 0.734), CGPoint(x: 0.156, y: 0.612),
    ])) }

    private static func forearmLobe() -> Path { smoothClosed([
        CGPoint(x: 0.150, y: 0.962), CGPoint(x: 0.208, y: 0.992), CGPoint(x: 0.214, y: 1.110),
        CGPoint(x: 0.190, y: 1.272), CGPoint(x: 0.156, y: 1.272), CGPoint(x: 0.146, y: 1.108),
    ]) }
    static func forearmFront() -> Path { mirrorPair(forearmLobe()) }
    static func forearmBack() -> Path { mirrorPair(forearmLobe()) }

    static func abdominals() -> Path {
        // Rectus abdominis: a 4×2 grid of softly-rounded cells split by the
        // linea alba, narrowing toward the navel.
        var p = Path()
        for row in 0..<4 {
            let y = 0.700 + Double(row) * 0.094
            let inset = 0.005 * Double(row)
            let w = 0.070 - inset
            p.addPath(roundedShape(at: CGRect(x: 0.430 + inset, y: y, width: w, height: 0.080),
                                   cornerRadius: 0.020))
            p.addPath(roundedShape(at: CGRect(x: 0.500, y: y, width: w, height: 0.080),
                                   cornerRadius: 0.020))
        }
        return p
    }

    static func obliques() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.404, y: 0.726), CGPoint(x: 0.412, y: 0.880), CGPoint(x: 0.402, y: 1.030),
        CGPoint(x: 0.356, y: 1.048), CGPoint(x: 0.334, y: 0.900), CGPoint(x: 0.346, y: 0.760),
    ])) }

    static func quadRectus() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.402, y: 1.492), CGPoint(x: 0.430, y: 1.502), CGPoint(x: 0.430, y: 1.700),
        CGPoint(x: 0.408, y: 1.858), CGPoint(x: 0.382, y: 1.836), CGPoint(x: 0.380, y: 1.640),
        CGPoint(x: 0.386, y: 1.520),
    ])) }

    static func quadLateralis() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.356, y: 1.500), CGPoint(x: 0.394, y: 1.512), CGPoint(x: 0.388, y: 1.680),
        CGPoint(x: 0.366, y: 1.812), CGPoint(x: 0.338, y: 1.756), CGPoint(x: 0.336, y: 1.620),
        CGPoint(x: 0.346, y: 1.540),
    ])) }

    static func quadMedialis() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.428, y: 1.696), CGPoint(x: 0.466, y: 1.724), CGPoint(x: 0.458, y: 1.842),
        CGPoint(x: 0.428, y: 1.884), CGPoint(x: 0.404, y: 1.858), CGPoint(x: 0.414, y: 1.760),
    ])) }

    static func adductors() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.474, y: 1.498), CGPoint(x: 0.492, y: 1.502), CGPoint(x: 0.488, y: 1.660),
        CGPoint(x: 0.466, y: 1.804), CGPoint(x: 0.452, y: 1.640), CGPoint(x: 0.458, y: 1.520),
    ])) }

    static func tibialis() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.400, y: 1.952), CGPoint(x: 0.432, y: 1.992), CGPoint(x: 0.426, y: 2.110),
        CGPoint(x: 0.402, y: 2.214), CGPoint(x: 0.380, y: 2.090), CGPoint(x: 0.384, y: 1.984),
    ])) }

    static func neck() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.476, y: 0.302), CGPoint(x: 0.492, y: 0.300), CGPoint(x: 0.490, y: 0.356),
        CGPoint(x: 0.470, y: 0.362), CGPoint(x: 0.460, y: 0.330),
    ])) }

    // MARK: - Back heads

    static func trapsUpper() -> Path { smoothClosed([
        CGPoint(x: 0.500, y: 0.350), CGPoint(x: 0.360, y: 0.452), CGPoint(x: 0.318, y: 0.520),
        CGPoint(x: 0.420, y: 0.600), CGPoint(x: 0.500, y: 0.642), CGPoint(x: 0.580, y: 0.600),
        CGPoint(x: 0.682, y: 0.520), CGPoint(x: 0.640, y: 0.452),
    ]) }

    static func trapsLower() -> Path { smoothClosed([
        CGPoint(x: 0.434, y: 0.610), CGPoint(x: 0.500, y: 0.598), CGPoint(x: 0.566, y: 0.610),
        CGPoint(x: 0.520, y: 0.862), CGPoint(x: 0.500, y: 0.940), CGPoint(x: 0.480, y: 0.862),
    ]) }

    static func tricepsLong() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.178, y: 0.506), CGPoint(x: 0.214, y: 0.558), CGPoint(x: 0.210, y: 0.700),
        CGPoint(x: 0.178, y: 0.752), CGPoint(x: 0.156, y: 0.700), CGPoint(x: 0.158, y: 0.558),
    ])) }

    static func tricepsLateral() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.214, y: 0.558), CGPoint(x: 0.252, y: 0.616), CGPoint(x: 0.232, y: 0.738),
        CGPoint(x: 0.198, y: 0.728), CGPoint(x: 0.204, y: 0.640),
    ])) }

    static func lats() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.336, y: 0.582), CGPoint(x: 0.300, y: 0.760), CGPoint(x: 0.344, y: 0.948),
        CGPoint(x: 0.456, y: 1.046), CGPoint(x: 0.492, y: 0.900), CGPoint(x: 0.492, y: 0.700),
        CGPoint(x: 0.430, y: 0.610),
    ])) }

    static func lowerBack() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.448, y: 1.040), CGPoint(x: 0.492, y: 1.048), CGPoint(x: 0.492, y: 1.222),
        CGPoint(x: 0.452, y: 1.236), CGPoint(x: 0.428, y: 1.140),
    ])) }

    static func glutes() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.496, y: 1.288), CGPoint(x: 0.496, y: 1.520), CGPoint(x: 0.404, y: 1.556),
        CGPoint(x: 0.330, y: 1.460), CGPoint(x: 0.356, y: 1.344), CGPoint(x: 0.440, y: 1.292),
    ])) }

    static func hamstrings() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.396, y: 1.556), CGPoint(x: 0.460, y: 1.566), CGPoint(x: 0.452, y: 1.740),
        CGPoint(x: 0.438, y: 1.892), CGPoint(x: 0.396, y: 1.924), CGPoint(x: 0.352, y: 1.882),
        CGPoint(x: 0.348, y: 1.700), CGPoint(x: 0.360, y: 1.578),
    ])) }

    static func gastrocnemius() -> Path {
        // Medial + lateral heads of the calf.
        let medial = smoothClosed([
            CGPoint(x: 0.392, y: 1.946), CGPoint(x: 0.432, y: 1.984), CGPoint(x: 0.442, y: 2.118),
            CGPoint(x: 0.410, y: 2.180), CGPoint(x: 0.392, y: 2.080), CGPoint(x: 0.388, y: 1.984),
        ])
        let lateral = smoothClosed([
            CGPoint(x: 0.392, y: 1.962), CGPoint(x: 0.396, y: 2.082), CGPoint(x: 0.374, y: 2.180),
            CGPoint(x: 0.344, y: 2.118), CGPoint(x: 0.352, y: 2.000), CGPoint(x: 0.372, y: 1.966),
        ])
        return mirrorPair(union([medial, lateral]))
    }

    static func soleus() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.404, y: 2.150), CGPoint(x: 0.422, y: 2.180), CGPoint(x: 0.406, y: 2.272),
        CGPoint(x: 0.382, y: 2.272), CGPoint(x: 0.364, y: 2.180), CGPoint(x: 0.382, y: 2.150),
    ])) }

    // MARK: - Skeleton underlay

    /// Faint skeletal scaffold drawn behind the muscles: skull, spine,
    /// ribcage, pelvis, long bones and ring joints. One strokable path.
    static func skeleton(facing front: Bool) -> Path {
        var p = Path()

        p.addEllipse(in: CGRect(x: 0.430, y: 0.066, width: 0.140, height: 0.200))
        p.move(to: CGPoint(x: 0.500, y: 0.300)); p.addLine(to: CGPoint(x: 0.500, y: 1.290))
        p.move(to: CGPoint(x: 0.500, y: 0.430)); p.addLine(to: CGPoint(x: 0.318, y: 0.470))
        p.move(to: CGPoint(x: 0.500, y: 0.430)); p.addLine(to: CGPoint(x: 0.682, y: 0.470))

        for i in 0..<4 {
            let y = 0.500 + Double(i) * 0.070
            let halfW = 0.150 - Double(i) * 0.020
            p.move(to: CGPoint(x: 0.500, y: y))
            p.addQuadCurve(to: CGPoint(x: 0.500 - halfW, y: y + 0.030),
                           control: CGPoint(x: 0.500 - halfW, y: y - 0.020))
            p.move(to: CGPoint(x: 0.500, y: y))
            p.addQuadCurve(to: CGPoint(x: 0.500 + halfW, y: y + 0.030),
                           control: CGPoint(x: 0.500 + halfW, y: y - 0.020))
        }

        p.addEllipse(in: CGRect(x: 0.374, y: 1.220, width: 0.252, height: 0.180))

        for s in [CGFloat(1), CGFloat(-1)] {
            func x(_ v: CGFloat) -> CGFloat { 0.5 + s * (v - 0.5) }
            p.move(to: CGPoint(x: x(0.770), y: 0.500))
            p.addLine(to: CGPoint(x: x(0.846), y: 0.945))
            p.addLine(to: CGPoint(x: x(0.812), y: 1.290))
            p.move(to: CGPoint(x: x(0.560), y: 1.360))
            p.addLine(to: CGPoint(x: x(0.560), y: 1.850))
            p.addLine(to: CGPoint(x: x(0.556), y: 2.300))
        }

        let joints: [(CGFloat, CGFloat)] = [
            (0.770, 0.500), (0.230, 0.500), (0.846, 0.945), (0.154, 0.945),
            (0.812, 1.290), (0.188, 1.290), (0.560, 1.360), (0.440, 1.360),
            (0.560, 1.850), (0.440, 1.850), (0.556, 2.300), (0.444, 2.300),
        ]
        for (jx, jy) in joints {
            p.addEllipse(in: CGRect(x: jx - 0.016, y: jy - 0.016, width: 0.032, height: 0.032))
        }

        return p
    }

    // MARK: - Definition grooves

    /// Thin separation lines over the fills — linea alba + ab inscriptions
    /// on the front, spinal furrow on the back — to sharpen the chart read.
    static func grooves(front: Bool) -> Path {
        var p = Path()
        if front {
            p.move(to: CGPoint(x: 0.5, y: 0.470)); p.addLine(to: CGPoint(x: 0.5, y: 1.060))
            for i in 0..<3 {
                let y = 0.748 + Double(i) * 0.094
                p.move(to: CGPoint(x: 0.436, y: y))
                p.addQuadCurve(to: CGPoint(x: 0.564, y: y), control: CGPoint(x: 0.5, y: y + 0.012))
            }
        } else {
            p.move(to: CGPoint(x: 0.5, y: 0.360)); p.addLine(to: CGPoint(x: 0.5, y: 1.230))
        }
        return p
    }

    // MARK: - Path dispatch

    /// Returns the path for a muscle head, dispatching to its builder so
    /// `MuscleMapView` can iterate over a set without a giant switch.
    static func path(for muscle: AnatomicalMuscle) -> Path {
        switch muscle {
        case .pecClavicular:    return pecClavicular()
        case .pecSternal:       return pecSternal()
        case .deltAnterior:     return deltAnterior()
        case .deltLateralFront: return deltLateralFront()
        case .biceps:           return biceps()
        case .forearmFront:     return forearmFront()
        case .abdominals:       return abdominals()
        case .obliques:         return obliques()
        case .quadRectus:       return quadRectus()
        case .quadLateralis:    return quadLateralis()
        case .quadMedialis:     return quadMedialis()
        case .adductors:        return adductors()
        case .tibialis:         return tibialis()
        case .neck:             return neck()

        case .trapsUpper:       return trapsUpper()
        case .trapsLower:       return trapsLower()
        case .deltPosterior:    return deltPosterior()
        case .deltLateralBack:  return deltLateralBack()
        case .tricepsLong:      return tricepsLong()
        case .tricepsLateral:   return tricepsLateral()
        case .lats:             return lats()
        case .lowerBack:        return lowerBack()
        case .forearmBack:      return forearmBack()
        case .glutes:           return glutes()
        case .hamstrings:       return hamstrings()
        case .gastrocnemius:    return gastrocnemius()
        case .soleus:           return soleus()
        }
    }

    // MARK: - Shape primitives

    /// Closed smooth outline through `points` (uniform Catmull-Rom → cubic
    /// Béziers). The curve passes through every point and wraps back to the
    /// first, so a handful of perimeter points yields an organic belly.
    private static func smoothClosed(_ points: [CGPoint], tension: CGFloat = 0) -> Path {
        var p = Path()
        let n = points.count
        guard n > 2 else { return p }
        let s = (1 - tension) / 6
        p.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * s, y: p1.y + (p2.y - p0.y) * s)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * s, y: p2.y - (p3.y - p1.y) * s)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        p.closeSubpath()
        return p
    }

    /// Mirrors a drawn side across the mid-line and unions it with the
    /// original for a symmetric left+right pair.
    private static func mirrorPair(_ left: Path) -> Path {
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    /// Unions several lobes into one path; each keeps its own outline so a
    /// multi-head muscle shows the separations between heads when stroked.
    private static func union(_ lobes: [Path]) -> Path {
        var p = Path()
        for lobe in lobes { p.addPath(lobe) }
        return p
    }

    private static func roundedShape(at rect: CGRect, cornerRadius: CGFloat = 0.04) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }
}
