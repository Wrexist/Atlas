import SwiftUI

/// Geometric definitions for the anatomical figure used by
/// `MuscleMapView`. Everything is drawn in a normalized
/// `[0…1] × [0…2.4]` coordinate space (1.0 wide, 2.4 tall — the
/// roughly 8-head canonical figure ratio). The view scales these up
/// to fit whatever pixel rect it receives through `GeometryReader`.
///
/// Both the body outline and every muscle are authored as a short list
/// of perimeter points run through `smoothClosed` (a closed
/// Catmull-Rom spline), so the shapes read as organic anatomy —
/// capped deltoids, fanned pectorals, teardrop quads, diamond calves,
/// winged lats — rather than geometric blobs, and stay easy to tune by
/// nudging a single point. Left/right pairs are derived from one drawn
/// side through `mirror`, so the figure is always perfectly symmetric.
/// A faint `skeleton` layer (skull, ribcage, spine, pelvis, long bones,
/// joints) sits under the muscles to ground the figure as a chart.
///
/// Keeping the geometry in one place means the muscle map can be
/// re-skinned (different stroke weights, palette, eventually
/// commissioned asset packs) without touching the view layer.
enum BodyAnatomy {

    /// Canonical aspect ratio of a single body figure (width / height).
    static let aspect: CGFloat = 1.0 / 2.4

    /// Reflects a point across the vertical mid-line (x → 1 − x). Used
    /// to derive every right-side shape from its drawn left-side twin
    /// so the figure can never drift out of symmetry.
    static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)

    // MARK: - Silhouette

    /// Right-half perimeter of the body, crown → crotch, traced down the
    /// outside of a broad-shouldered, V-tapered athletic figure (head,
    /// neck, deltoid, arm with a bicep/forearm swell, hand, armpit notch,
    /// lat, waist, hip, thigh, calf, foot). The left half is the mirror
    /// of these points, so the outline is exactly symmetric.
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

    /// One smooth, continuous humanoid outline built by smoothing the
    /// right-half perimeter together with its mirror.
    static func frontSilhouette() -> Path {
        var pts = rightHalf
        pts += rightHalf.dropFirst().dropLast().reversed().map {
            CGPoint(x: 1 - $0.x, y: $0.y)
        }
        return smoothClosed(pts)
    }

    /// The back outline matches the front silhouette; the back-only
    /// muscle + skeleton layers convey the difference in view.
    static func backSilhouette() -> Path { frontSilhouette() }

    // MARK: - Front muscles

    static func chest() -> Path { mirrorPair(pecLobe()) }

    private static func pecLobe() -> Path {
        // Fanned pectoral shield, leaving a thin sternum gap at the
        // mid-line where it meets its mirror.
        smoothClosed([
            CGPoint(x: 0.495, y: 0.452), CGPoint(x: 0.392, y: 0.456), CGPoint(x: 0.318, y: 0.486),
            CGPoint(x: 0.300, y: 0.560), CGPoint(x: 0.336, y: 0.636), CGPoint(x: 0.430, y: 0.654),
            CGPoint(x: 0.495, y: 0.620),
        ])
    }

    static func abdominals() -> Path {
        // Rectus abdominis: a 4×2 grid of softly-rounded cells split by
        // the linea alba, narrowing toward the navel.
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

    static func obliques() -> Path { mirrorPair(obliqueSlab()) }

    private static func obliqueSlab() -> Path {
        smoothClosed([
            CGPoint(x: 0.404, y: 0.726), CGPoint(x: 0.412, y: 0.880), CGPoint(x: 0.402, y: 1.030),
            CGPoint(x: 0.356, y: 1.048), CGPoint(x: 0.334, y: 0.900), CGPoint(x: 0.346, y: 0.760),
        ])
    }

    static func shouldersFront() -> Path { mirrorPair(deltoidCap()) }

    private static func deltoidCap() -> Path {
        // Rounded cap wrapping the shoulder joint — wide over the top,
        // tapering where it meets the pec and biceps.
        smoothClosed([
            CGPoint(x: 0.300, y: 0.428), CGPoint(x: 0.214, y: 0.412), CGPoint(x: 0.150, y: 0.470),
            CGPoint(x: 0.146, y: 0.556), CGPoint(x: 0.196, y: 0.612), CGPoint(x: 0.268, y: 0.582),
            CGPoint(x: 0.300, y: 0.508),
        ])
    }

    static func neckFront() -> Path { mirrorPair(neckStrap()) }

    private static func neckStrap() -> Path {
        // Sternocleidomastoid — a soft strap from the jaw to the
        // sternal notch.
        smoothClosed([
            CGPoint(x: 0.476, y: 0.302), CGPoint(x: 0.492, y: 0.300), CGPoint(x: 0.490, y: 0.356),
            CGPoint(x: 0.470, y: 0.362), CGPoint(x: 0.460, y: 0.330),
        ])
    }

    static func bicepsLeft() -> Path { bicepsLobe() }
    static func bicepsRight() -> Path { bicepsLobe().applying(mirror) }

    private static func bicepsLobe() -> Path {
        smoothClosed([
            CGPoint(x: 0.205, y: 0.500), CGPoint(x: 0.256, y: 0.606), CGPoint(x: 0.232, y: 0.730),
            CGPoint(x: 0.172, y: 0.734), CGPoint(x: 0.156, y: 0.612),
        ])
    }

    static func forearmsFront() -> Path { mirrorPair(forearmLobe()) }

    private static func forearmLobe() -> Path {
        smoothClosed([
            CGPoint(x: 0.150, y: 0.962), CGPoint(x: 0.208, y: 0.992), CGPoint(x: 0.214, y: 1.110),
            CGPoint(x: 0.190, y: 1.272), CGPoint(x: 0.156, y: 1.272), CGPoint(x: 0.146, y: 1.108),
        ])
    }

    static func quadricepsLeft() -> Path { quadLobe() }
    static func quadricepsRight() -> Path { quadLobe().applying(mirror) }

    private static func quadLobe() -> Path {
        // Teardrop quad with an outer vastus-lateralis sweep and an inner
        // vastus-medialis bulge just above the knee.
        smoothClosed([
            CGPoint(x: 0.404, y: 1.474), CGPoint(x: 0.470, y: 1.494), CGPoint(x: 0.460, y: 1.660),
            CGPoint(x: 0.452, y: 1.840), CGPoint(x: 0.404, y: 1.902), CGPoint(x: 0.346, y: 1.852),
            CGPoint(x: 0.336, y: 1.640), CGPoint(x: 0.356, y: 1.500),
        ])
    }

    static func adductors() -> Path { mirrorPair(adductorStrap()) }

    private static func adductorStrap() -> Path {
        smoothClosed([
            CGPoint(x: 0.474, y: 1.498), CGPoint(x: 0.492, y: 1.502), CGPoint(x: 0.488, y: 1.660),
            CGPoint(x: 0.466, y: 1.804), CGPoint(x: 0.452, y: 1.640), CGPoint(x: 0.458, y: 1.520),
        ])
    }

    static func calvesFront() -> Path { mirrorPair(tibialisLobe()) }

    private static func tibialisLobe() -> Path {
        smoothClosed([
            CGPoint(x: 0.400, y: 1.952), CGPoint(x: 0.432, y: 1.992), CGPoint(x: 0.426, y: 2.110),
            CGPoint(x: 0.402, y: 2.214), CGPoint(x: 0.380, y: 2.090), CGPoint(x: 0.384, y: 1.984),
        ])
    }

    // MARK: - Back muscles

    static func traps() -> Path {
        // Upper-trap kite flaring over the shoulders, tapering to a
        // lower-trap point down the spine.
        smoothClosed([
            CGPoint(x: 0.500, y: 0.350), CGPoint(x: 0.360, y: 0.452), CGPoint(x: 0.318, y: 0.520),
            CGPoint(x: 0.430, y: 0.612), CGPoint(x: 0.470, y: 0.880), CGPoint(x: 0.500, y: 0.940),
            CGPoint(x: 0.530, y: 0.880), CGPoint(x: 0.570, y: 0.612), CGPoint(x: 0.682, y: 0.520),
            CGPoint(x: 0.640, y: 0.452),
        ])
    }

    static func lats() -> Path { mirrorPair(latWing()) }

    private static func latWing() -> Path {
        // Broad wing — wide under the armpit, sweeping in to the waist
        // along the spine.
        smoothClosed([
            CGPoint(x: 0.336, y: 0.582), CGPoint(x: 0.300, y: 0.760), CGPoint(x: 0.344, y: 0.948),
            CGPoint(x: 0.456, y: 1.046), CGPoint(x: 0.492, y: 0.900), CGPoint(x: 0.492, y: 0.700),
            CGPoint(x: 0.430, y: 0.610),
        ])
    }

    static func lowerBack() -> Path { mirrorPair(erectorColumn()) }

    private static func erectorColumn() -> Path {
        // One erector-spinae column beside the lumbar spine.
        smoothClosed([
            CGPoint(x: 0.448, y: 1.040), CGPoint(x: 0.492, y: 1.048), CGPoint(x: 0.492, y: 1.222),
            CGPoint(x: 0.452, y: 1.236), CGPoint(x: 0.428, y: 1.140),
        ])
    }

    static func shouldersBack() -> Path { shouldersFront() }

    static func tricepsLeft() -> Path { tricepsLobe() }
    static func tricepsRight() -> Path { tricepsLobe().applying(mirror) }

    private static func tricepsLobe() -> Path {
        smoothClosed([
            CGPoint(x: 0.200, y: 0.504), CGPoint(x: 0.254, y: 0.618), CGPoint(x: 0.230, y: 0.758),
            CGPoint(x: 0.166, y: 0.752), CGPoint(x: 0.152, y: 0.600),
        ])
    }

    static func forearmsBack() -> Path { forearmsFront() }

    static func glutesLeft() -> Path { gluteLobe() }
    static func glutesRight() -> Path { gluteLobe().applying(mirror) }

    private static func gluteLobe() -> Path {
        smoothClosed([
            CGPoint(x: 0.496, y: 1.288), CGPoint(x: 0.496, y: 1.520), CGPoint(x: 0.404, y: 1.556),
            CGPoint(x: 0.330, y: 1.460), CGPoint(x: 0.356, y: 1.344), CGPoint(x: 0.440, y: 1.292),
        ])
    }

    static func hamstringsLeft() -> Path { hamstringLobe() }
    static func hamstringsRight() -> Path { hamstringLobe().applying(mirror) }

    private static func hamstringLobe() -> Path {
        smoothClosed([
            CGPoint(x: 0.396, y: 1.556), CGPoint(x: 0.460, y: 1.566), CGPoint(x: 0.452, y: 1.740),
            CGPoint(x: 0.438, y: 1.892), CGPoint(x: 0.396, y: 1.924), CGPoint(x: 0.352, y: 1.882),
            CGPoint(x: 0.348, y: 1.700), CGPoint(x: 0.360, y: 1.578),
        ])
    }

    static func calvesBack() -> Path { mirrorPair(gastrocLobe()) }

    private static func gastrocLobe() -> Path {
        // Gastrocnemius diamond — two heads bulging from the back of the
        // lower leg.
        smoothClosed([
            CGPoint(x: 0.392, y: 1.946), CGPoint(x: 0.452, y: 2.040), CGPoint(x: 0.436, y: 2.180),
            CGPoint(x: 0.392, y: 2.262), CGPoint(x: 0.348, y: 2.180), CGPoint(x: 0.332, y: 2.040),
        ])
    }

    // MARK: - Skeleton underlay

    /// Faint skeletal scaffold drawn behind the muscles to ground the
    /// figure as an anatomy chart: skull, spine, ribcage, pelvis, the
    /// long bones, and ring joints. Returned as one strokable path.
    static func skeleton(facing front: Bool) -> Path {
        var p = Path()

        // Skull
        p.addEllipse(in: CGRect(x: 0.430, y: 0.066, width: 0.140, height: 0.200))
        // Cervical → lumbar spine
        p.move(to: CGPoint(x: 0.500, y: 0.300))
        p.addLine(to: CGPoint(x: 0.500, y: 1.290))
        // Clavicles
        p.move(to: CGPoint(x: 0.500, y: 0.430)); p.addLine(to: CGPoint(x: 0.318, y: 0.470))
        p.move(to: CGPoint(x: 0.500, y: 0.430)); p.addLine(to: CGPoint(x: 0.682, y: 0.470))

        // Ribcage — a tapered cage of paired arcs
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

        // Pelvis
        p.addEllipse(in: CGRect(x: 0.374, y: 1.220, width: 0.252, height: 0.180))

        // Long bones — humerus + forearm, femur + tibia (each side)
        for s in [CGFloat(1), CGFloat(-1)] {
            func x(_ v: CGFloat) -> CGFloat { 0.5 + s * (v - 0.5) }
            p.move(to: CGPoint(x: x(0.770), y: 0.500))
            p.addLine(to: CGPoint(x: x(0.846), y: 0.945))
            p.addLine(to: CGPoint(x: x(0.812), y: 1.290))
            p.move(to: CGPoint(x: x(0.560), y: 1.360))
            p.addLine(to: CGPoint(x: x(0.560), y: 1.850))
            p.addLine(to: CGPoint(x: x(0.556), y: 2.300))
        }

        // Joint rings — shoulders, elbows, wrists, hips, knees, ankles
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

    /// Thin muscle-separation lines drawn over the fills to give the
    /// sculpted read of an anatomy chart — linea alba + ab inscriptions
    /// and the quad / calf splits on the front; spinal furrow and
    /// hamstring / calf splits on the back. Returned as one strokable
    /// path so the view lays it down in a single shadowed pass.
    static func grooves(front: Bool) -> Path {
        var p = Path()

        func seg(_ a: CGPoint, _ b: CGPoint) {
            p.move(to: a); p.addLine(to: b)
            p.move(to: a.applying(mirror)); p.addLine(to: b.applying(mirror))
        }

        if front {
            // Linea alba (centre line of the abs)
            p.move(to: CGPoint(x: 0.5, y: 0.470)); p.addLine(to: CGPoint(x: 0.5, y: 1.060))
            // Tendinous inscriptions across the six-pack
            for i in 0..<3 {
                let y = 0.748 + Double(i) * 0.094
                p.move(to: CGPoint(x: 0.436, y: y))
                p.addQuadCurve(to: CGPoint(x: 0.564, y: y), control: CGPoint(x: 0.5, y: y + 0.012))
            }
            // Quad sweep + calf split
            seg(CGPoint(x: 0.404, y: 1.520), CGPoint(x: 0.402, y: 1.840))
            seg(CGPoint(x: 0.392, y: 1.992), CGPoint(x: 0.392, y: 2.200))
        } else {
            // Spinal furrow
            p.move(to: CGPoint(x: 0.5, y: 0.360)); p.addLine(to: CGPoint(x: 0.5, y: 1.230))
            // Hamstring + calf splits
            seg(CGPoint(x: 0.392, y: 1.580), CGPoint(x: 0.392, y: 1.880))
            seg(CGPoint(x: 0.392, y: 1.992), CGPoint(x: 0.392, y: 2.220))
        }
        return p
    }

    // MARK: - Path dispatch

    /// Returns the path for a muscle case, dispatching to the right
    /// builder. Centralised so `MuscleMapView` can iterate over a
    /// `Set<AnatomicalMuscle>` without a giant switch in the body.
    static func path(for muscle: AnatomicalMuscle) -> Path {
        switch muscle {
        case .chest:           return chest()
        case .abdominals:      return abdominals()
        case .obliques:        return obliques()
        case .shouldersFront:  return shouldersFront()
        case .neckFront:       return neckFront()
        case .bicepsLeft:      return bicepsLeft()
        case .bicepsRight:     return bicepsRight()
        case .forearmsFront:   return forearmsFront()
        case .quadricepsLeft:  return quadricepsLeft()
        case .quadricepsRight: return quadricepsRight()
        case .adductors:       return adductors()
        case .calvesFront:     return calvesFront()

        case .traps:           return traps()
        case .lats:            return lats()
        case .lowerBack:       return lowerBack()
        case .shouldersBack:   return shouldersBack()
        case .tricepsLeft:     return tricepsLeft()
        case .tricepsRight:    return tricepsRight()
        case .forearmsBack:    return forearmsBack()
        case .glutesLeft:      return glutesLeft()
        case .glutesRight:     return glutesRight()
        case .hamstringsLeft:  return hamstringsLeft()
        case .hamstringsRight: return hamstringsRight()
        case .calvesBack:      return calvesBack()
        }
    }

    // MARK: - Shape primitives

    /// Builds a closed, smooth outline through `points` using a uniform
    /// Catmull-Rom spline converted to cubic Béziers. The curve passes
    /// through every point and wraps back to the first, so a handful of
    /// perimeter points yields an organic muscle belly.
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

    /// Mirrors a single drawn side across the mid-line and unions it with
    /// the original, giving a perfectly symmetric left+right pair.
    private static func mirrorPair(_ left: Path) -> Path {
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    private static func roundedShape(at rect: CGRect, cornerRadius: CGFloat = 0.04) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }
}
