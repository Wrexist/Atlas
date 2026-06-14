import SwiftUI

/// Geometric definitions for the anatomical figure used by
/// `MuscleMapView`. Everything is drawn in a normalized
/// `[0…1] × [0…2.4]` coordinate space (1.0 wide, 2.4 tall — the
/// roughly 8-head canonical figure ratio). The view scales these up
/// to fit whatever pixel rect it receives through `GeometryReader`.
///
/// The figure follows true 8-head landmarks so it reads as a real
/// athletic body rather than a stylised blob: chin at 0.30, shoulder
/// line at 0.46, navel at 1.00, crotch at half height (1.26), knee at
/// 1.82 and ankle at 2.29. Arms hang slightly abducted so the arm
/// heads (delts, biceps, triceps, forearms) stay visually separate
/// from the torso.
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

    /// Right-half perimeter, crown → crotch: skull, jaw, neck, trap slope
    /// to the acromion, the deltoid cap, down the outside of a slightly
    /// abducted arm to the hand, back up the inner arm to the armpit,
    /// then the torso side (chest, waist, hip flare) and down the leg
    /// (thigh, knee, calf, ankle, foot) to the crotch at mid-line. The
    /// left half is the mirror of these points, so the outline is
    /// exactly symmetric.
    private static let rightHalf: [CGPoint] = [
        CGPoint(x: 0.500, y: 0.040),
        CGPoint(x: 0.568, y: 0.085), CGPoint(x: 0.583, y: 0.165), CGPoint(x: 0.552, y: 0.260),
        CGPoint(x: 0.530, y: 0.300), CGPoint(x: 0.528, y: 0.365),
        CGPoint(x: 0.600, y: 0.408), CGPoint(x: 0.700, y: 0.435), CGPoint(x: 0.790, y: 0.462),
        CGPoint(x: 0.836, y: 0.530), CGPoint(x: 0.842, y: 0.610),
        CGPoint(x: 0.836, y: 0.700), CGPoint(x: 0.848, y: 0.800), CGPoint(x: 0.860, y: 0.880),
        CGPoint(x: 0.888, y: 1.000), CGPoint(x: 0.896, y: 1.100), CGPoint(x: 0.886, y: 1.200),
        CGPoint(x: 0.920, y: 1.290), CGPoint(x: 0.872, y: 1.350), CGPoint(x: 0.836, y: 1.290),
        CGPoint(x: 0.836, y: 1.180), CGPoint(x: 0.812, y: 1.020), CGPoint(x: 0.776, y: 0.880),
        CGPoint(x: 0.760, y: 0.760), CGPoint(x: 0.742, y: 0.640), CGPoint(x: 0.726, y: 0.585),
        CGPoint(x: 0.700, y: 0.660), CGPoint(x: 0.672, y: 0.820), CGPoint(x: 0.660, y: 0.960),
        CGPoint(x: 0.688, y: 1.060), CGPoint(x: 0.706, y: 1.160),
        CGPoint(x: 0.700, y: 1.260), CGPoint(x: 0.690, y: 1.400), CGPoint(x: 0.668, y: 1.560),
        CGPoint(x: 0.636, y: 1.730), CGPoint(x: 0.630, y: 1.820),
        CGPoint(x: 0.650, y: 1.950), CGPoint(x: 0.636, y: 2.060), CGPoint(x: 0.596, y: 2.200),
        CGPoint(x: 0.578, y: 2.290), CGPoint(x: 0.610, y: 2.350), CGPoint(x: 0.560, y: 2.375),
        CGPoint(x: 0.518, y: 2.360), CGPoint(x: 0.520, y: 2.290),
        CGPoint(x: 0.528, y: 2.140), CGPoint(x: 0.540, y: 1.990), CGPoint(x: 0.528, y: 1.870),
        CGPoint(x: 0.532, y: 1.760), CGPoint(x: 0.548, y: 1.600), CGPoint(x: 0.560, y: 1.440),
        CGPoint(x: 0.540, y: 1.330), CGPoint(x: 0.500, y: 1.270),
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

    static func neck() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.503, y: 0.305), CGPoint(x: 0.516, y: 0.317), CGPoint(x: 0.531, y: 0.383),
        CGPoint(x: 0.596, y: 0.418), CGPoint(x: 0.566, y: 0.444), CGPoint(x: 0.504, y: 0.436),
    ])) }

    static func pecClavicular() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.502, y: 0.448), CGPoint(x: 0.600, y: 0.450), CGPoint(x: 0.706, y: 0.474),
        CGPoint(x: 0.712, y: 0.508), CGPoint(x: 0.608, y: 0.522), CGPoint(x: 0.502, y: 0.516),
    ])) }

    static func pecSternal() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.502, y: 0.518), CGPoint(x: 0.610, y: 0.524), CGPoint(x: 0.706, y: 0.514),
        CGPoint(x: 0.716, y: 0.585), CGPoint(x: 0.691, y: 0.653), CGPoint(x: 0.618, y: 0.700),
        CGPoint(x: 0.540, y: 0.690), CGPoint(x: 0.504, y: 0.662),
    ])) }

    static func deltAnterior() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.712, y: 0.452), CGPoint(x: 0.766, y: 0.470), CGPoint(x: 0.788, y: 0.530),
        CGPoint(x: 0.760, y: 0.590), CGPoint(x: 0.726, y: 0.560), CGPoint(x: 0.708, y: 0.500),
    ])) }

    /// Lateral deltoid cap — the same head is visible from front and back;
    /// `deltLateralFront`/`deltLateralBack` share this geometry.
    private static func deltLateralCap() -> Path { smoothClosed([
        CGPoint(x: 0.775, y: 0.465), CGPoint(x: 0.808, y: 0.496), CGPoint(x: 0.832, y: 0.560),
        CGPoint(x: 0.820, y: 0.622), CGPoint(x: 0.790, y: 0.602), CGPoint(x: 0.778, y: 0.530),
    ]) }
    static func deltLateralFront() -> Path { mirrorPair(deltLateralCap()) }
    static func deltLateralBack() -> Path { mirrorPair(deltLateralCap()) }

    static func biceps() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.760, y: 0.596), CGPoint(x: 0.810, y: 0.622), CGPoint(x: 0.828, y: 0.730),
        CGPoint(x: 0.812, y: 0.848), CGPoint(x: 0.782, y: 0.857), CGPoint(x: 0.767, y: 0.740),
        CGPoint(x: 0.753, y: 0.647),
    ])) }

    private static func forearmLobe() -> Path { smoothClosed([
        CGPoint(x: 0.784, y: 0.870), CGPoint(x: 0.836, y: 0.906), CGPoint(x: 0.872, y: 1.016),
        CGPoint(x: 0.876, y: 1.130), CGPoint(x: 0.852, y: 1.226), CGPoint(x: 0.846, y: 1.232),
        CGPoint(x: 0.834, y: 1.085), CGPoint(x: 0.806, y: 0.954),
    ]) }
    static func forearmFront() -> Path { mirrorPair(forearmLobe()) }
    static func forearmBack() -> Path { mirrorPair(forearmLobe()) }

    static func abdominals() -> Path {
        // Rectus abdominis: three paired six-pack rows split by the linea
        // alba, narrowing slightly per row, over a taller lower-abs slab.
        var p = Path()
        for row in 0..<3 {
            let y = 0.715 + Double(row) * 0.097
            let w = 0.086 - 0.004 * Double(row)
            p.addPath(roundedShape(at: CGRect(x: 0.506, y: y, width: w, height: 0.088),
                                   cornerRadius: 0.024))
            p.addPath(roundedShape(at: CGRect(x: 0.494 - w, y: y, width: w, height: 0.088),
                                   cornerRadius: 0.024))
        }
        p.addPath(roundedShape(at: CGRect(x: 0.506, y: 1.006, width: 0.074, height: 0.140),
                               cornerRadius: 0.032))
        p.addPath(roundedShape(at: CGRect(x: 0.420, y: 1.006, width: 0.074, height: 0.140),
                               cornerRadius: 0.032))
        return p
    }

    static func obliques() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.602, y: 0.700), CGPoint(x: 0.648, y: 0.746), CGPoint(x: 0.652, y: 0.898),
        CGPoint(x: 0.678, y: 1.061), CGPoint(x: 0.660, y: 1.130), CGPoint(x: 0.616, y: 1.090),
        CGPoint(x: 0.600, y: 0.900),
    ])) }

    static func quadRectus() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.600, y: 1.268), CGPoint(x: 0.648, y: 1.340), CGPoint(x: 0.658, y: 1.520),
        CGPoint(x: 0.636, y: 1.670), CGPoint(x: 0.604, y: 1.738), CGPoint(x: 0.576, y: 1.650),
        CGPoint(x: 0.570, y: 1.470), CGPoint(x: 0.582, y: 1.330),
    ])) }

    static func quadLateralis() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.648, y: 1.290), CGPoint(x: 0.680, y: 1.399), CGPoint(x: 0.659, y: 1.554),
        CGPoint(x: 0.631, y: 1.702), CGPoint(x: 0.625, y: 1.735), CGPoint(x: 0.642, y: 1.620),
        CGPoint(x: 0.650, y: 1.450),
    ])) }

    static func quadMedialis() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.572, y: 1.560), CGPoint(x: 0.598, y: 1.620), CGPoint(x: 0.602, y: 1.740),
        CGPoint(x: 0.578, y: 1.802), CGPoint(x: 0.552, y: 1.760), CGPoint(x: 0.553, y: 1.651),
    ])) }

    static func adductors() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.520, y: 1.270), CGPoint(x: 0.566, y: 1.296), CGPoint(x: 0.584, y: 1.420),
        CGPoint(x: 0.572, y: 1.580), CGPoint(x: 0.561, y: 1.567), CGPoint(x: 0.569, y: 1.427),
        CGPoint(x: 0.543, y: 1.310),
    ])) }

    static func tibialis() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.578, y: 1.872), CGPoint(x: 0.622, y: 1.940), CGPoint(x: 0.624, y: 2.068),
        CGPoint(x: 0.585, y: 2.203), CGPoint(x: 0.573, y: 2.247), CGPoint(x: 0.570, y: 2.100),
        CGPoint(x: 0.570, y: 1.960),
    ])) }

    // MARK: - Back heads

    static func trapsUpper() -> Path { smoothClosed([
        CGPoint(x: 0.500, y: 0.360), CGPoint(x: 0.620, y: 0.432), CGPoint(x: 0.720, y: 0.468),
        CGPoint(x: 0.610, y: 0.556), CGPoint(x: 0.500, y: 0.618),
        CGPoint(x: 0.390, y: 0.556), CGPoint(x: 0.280, y: 0.468), CGPoint(x: 0.380, y: 0.432),
    ]) }

    static func trapsLower() -> Path { smoothClosed([
        CGPoint(x: 0.500, y: 0.600), CGPoint(x: 0.566, y: 0.585), CGPoint(x: 0.586, y: 0.622),
        CGPoint(x: 0.524, y: 0.820), CGPoint(x: 0.500, y: 0.900),
        CGPoint(x: 0.476, y: 0.820), CGPoint(x: 0.414, y: 0.622), CGPoint(x: 0.434, y: 0.585),
    ]) }

    static func rhomboids() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.506, y: 0.572), CGPoint(x: 0.548, y: 0.598), CGPoint(x: 0.560, y: 0.692),
        CGPoint(x: 0.528, y: 0.728), CGPoint(x: 0.506, y: 0.706),
    ])) }

    static func deltPosterior() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.712, y: 0.470), CGPoint(x: 0.762, y: 0.480), CGPoint(x: 0.790, y: 0.540),
        CGPoint(x: 0.766, y: 0.610), CGPoint(x: 0.744, y: 0.596), CGPoint(x: 0.706, y: 0.520),
    ])) }

    static func tricepsLong() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.748, y: 0.605), CGPoint(x: 0.788, y: 0.638), CGPoint(x: 0.795, y: 0.760),
        CGPoint(x: 0.783, y: 0.861), CGPoint(x: 0.782, y: 0.855), CGPoint(x: 0.764, y: 0.717),
    ])) }

    static func tricepsLateral() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.790, y: 0.618), CGPoint(x: 0.829, y: 0.650), CGPoint(x: 0.832, y: 0.761),
        CGPoint(x: 0.824, y: 0.852), CGPoint(x: 0.798, y: 0.846), CGPoint(x: 0.798, y: 0.722),
    ])) }

    static func lats() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.692, y: 0.582), CGPoint(x: 0.700, y: 0.640), CGPoint(x: 0.678, y: 0.730),
        CGPoint(x: 0.658, y: 0.840), CGPoint(x: 0.616, y: 0.950), CGPoint(x: 0.560, y: 1.040),
        CGPoint(x: 0.516, y: 1.072), CGPoint(x: 0.516, y: 0.880), CGPoint(x: 0.554, y: 0.716),
        CGPoint(x: 0.628, y: 0.616),
    ])) }

    static func lowerBack() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.508, y: 0.940), CGPoint(x: 0.552, y: 0.980), CGPoint(x: 0.560, y: 1.120),
        CGPoint(x: 0.540, y: 1.240), CGPoint(x: 0.510, y: 1.250),
    ])) }

    static func glutes() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.506, y: 1.170), CGPoint(x: 0.560, y: 1.192), CGPoint(x: 0.640, y: 1.272),
        CGPoint(x: 0.660, y: 1.360), CGPoint(x: 0.620, y: 1.430), CGPoint(x: 0.570, y: 1.441),
        CGPoint(x: 0.565, y: 1.390),
    ])) }

    static func gluteMedius() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.600, y: 1.130), CGPoint(x: 0.656, y: 1.160), CGPoint(x: 0.676, y: 1.240),
        CGPoint(x: 0.640, y: 1.292), CGPoint(x: 0.592, y: 1.262), CGPoint(x: 0.580, y: 1.180),
    ])) }

    static func hamstringLateral() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.606, y: 1.456), CGPoint(x: 0.662, y: 1.484), CGPoint(x: 0.648, y: 1.616),
        CGPoint(x: 0.621, y: 1.767), CGPoint(x: 0.614, y: 1.806), CGPoint(x: 0.596, y: 1.640),
        CGPoint(x: 0.598, y: 1.520),
    ])) }

    static func hamstringMedial() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.570, y: 1.448), CGPoint(x: 0.594, y: 1.468), CGPoint(x: 0.600, y: 1.640),
        CGPoint(x: 0.586, y: 1.794), CGPoint(x: 0.554, y: 1.824), CGPoint(x: 0.553, y: 1.652),
        CGPoint(x: 0.566, y: 1.523),
    ])) }

    static func gastrocnemius() -> Path {
        // Medial + lateral heads of the calf.
        let medial = smoothClosed([
            CGPoint(x: 0.560, y: 1.880), CGPoint(x: 0.592, y: 1.900), CGPoint(x: 0.602, y: 2.000),
            CGPoint(x: 0.590, y: 2.090), CGPoint(x: 0.562, y: 2.130), CGPoint(x: 0.548, y: 2.030),
            CGPoint(x: 0.546, y: 1.940),
        ])
        let lateral = smoothClosed([
            CGPoint(x: 0.598, y: 1.890), CGPoint(x: 0.634, y: 1.922), CGPoint(x: 0.636, y: 2.009),
            CGPoint(x: 0.616, y: 2.096), CGPoint(x: 0.606, y: 2.082), CGPoint(x: 0.598, y: 1.990),
        ])
        return mirrorPair(union([medial, lateral]))
    }

    static func soleus() -> Path { mirrorPair(smoothClosed([
        CGPoint(x: 0.566, y: 2.120), CGPoint(x: 0.610, y: 2.112), CGPoint(x: 0.598, y: 2.155),
        CGPoint(x: 0.571, y: 2.256), CGPoint(x: 0.568, y: 2.271), CGPoint(x: 0.556, y: 2.180),
    ])) }

    // MARK: - Skeleton underlay

    /// Faint skeletal scaffold drawn behind the muscles: skull, spine,
    /// ribcage, pelvis, long bones and ring joints. One strokable path.
    static func skeleton(facing front: Bool) -> Path {
        var p = Path()

        p.addEllipse(in: CGRect(x: 0.435, y: 0.075, width: 0.130, height: 0.200))
        p.move(to: CGPoint(x: 0.500, y: 0.300)); p.addLine(to: CGPoint(x: 0.500, y: 1.160))
        p.move(to: CGPoint(x: 0.500, y: 0.430)); p.addLine(to: CGPoint(x: 0.790, y: 0.465))
        p.move(to: CGPoint(x: 0.500, y: 0.430)); p.addLine(to: CGPoint(x: 0.210, y: 0.465))

        for i in 0..<4 {
            let y = 0.510 + Double(i) * 0.062
            let halfW = 0.165 - Double(i) * 0.018
            p.move(to: CGPoint(x: 0.500, y: y))
            p.addQuadCurve(to: CGPoint(x: 0.500 - halfW, y: y + 0.030),
                           control: CGPoint(x: 0.500 - halfW, y: y - 0.020))
            p.move(to: CGPoint(x: 0.500, y: y))
            p.addQuadCurve(to: CGPoint(x: 0.500 + halfW, y: y + 0.030),
                           control: CGPoint(x: 0.500 + halfW, y: y - 0.020))
        }

        p.addEllipse(in: CGRect(x: 0.385, y: 1.060, width: 0.230, height: 0.170))

        for s in [CGFloat(1), CGFloat(-1)] {
            func x(_ v: CGFloat) -> CGFloat { 0.5 + s * (v - 0.5) }
            p.move(to: CGPoint(x: x(0.790), y: 0.470))
            p.addLine(to: CGPoint(x: x(0.820), y: 0.880))
            p.addLine(to: CGPoint(x: x(0.860), y: 1.200))
            p.move(to: CGPoint(x: x(0.600), y: 1.180))
            p.addLine(to: CGPoint(x: x(0.580), y: 1.820))
            p.addLine(to: CGPoint(x: x(0.550), y: 2.290))
        }

        let joints: [(CGFloat, CGFloat)] = [
            (0.790, 0.470), (0.210, 0.470), (0.820, 0.880), (0.180, 0.880),
            (0.860, 1.200), (0.140, 1.200), (0.600, 1.180), (0.400, 1.180),
            (0.580, 1.820), (0.420, 1.820), (0.550, 2.290), (0.450, 2.290),
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
            p.move(to: CGPoint(x: 0.5, y: 0.450)); p.addLine(to: CGPoint(x: 0.5, y: 1.130))
            for i in 0..<3 {
                let y = 0.806 + Double(i) * 0.097
                p.move(to: CGPoint(x: 0.412, y: y))
                p.addQuadCurve(to: CGPoint(x: 0.588, y: y), control: CGPoint(x: 0.5, y: y + 0.014))
            }
        } else {
            p.move(to: CGPoint(x: 0.5, y: 0.360)); p.addLine(to: CGPoint(x: 0.5, y: 1.170))
        }
        return p
    }

    // MARK: - Fiber striations

    /// Fiber direction per muscle head, in degrees from vertical for the
    /// RIGHT side of the body; the renderer mirrors the angle for the
    /// left half. Fan-shaped muscles (pecs, delts, traps, lats, glutes)
    /// tilt strongly; limb muscles run close to vertical — matching how
    /// the fibers actually lie, which is what sells the écorché read.
    static func fiberAngle(for muscle: AnatomicalMuscle) -> CGFloat {
        switch muscle {
        case .neck:             return 15
        case .pecClavicular:    return 70
        case .pecSternal:       return 80
        case .deltAnterior:     return 12
        case .deltLateralFront: return 8
        case .biceps:           return 4
        case .forearmFront:     return 6
        case .abdominals:       return 0
        case .obliques:         return 20
        case .quadRectus:       return 4
        case .quadLateralis:    return 8
        case .quadMedialis:     return 25
        case .adductors:        return 12
        case .tibialis:         return 4
        case .trapsUpper:       return 40
        case .trapsLower:       return 15
        case .rhomboids:        return 30
        case .deltPosterior:    return 12
        case .deltLateralBack:  return 8
        case .tricepsLong:      return 4
        case .tricepsLateral:   return 6
        case .forearmBack:      return 6
        case .lats:             return 32
        case .lowerBack:        return 2
        case .glutes:           return 35
        case .gluteMedius:      return 18
        case .hamstringLateral: return 3
        case .hamstringMedial:  return 3
        case .gastrocnemius:    return 5
        case .soleus:           return 5
        }
    }

    /// Parallel, slightly bowed striation lines crossing `rect` at
    /// `angleDegrees` from vertical, in normalized body space. The
    /// renderer clips the result to the muscle's path (per body half,
    /// with the angle mirrored) so each belly reads as fibrous tissue
    /// rather than a flat fill. Lines bow outward most at the centre of
    /// the belly, wrapping the volume.
    static func fibers(in rect: CGRect, angleDegrees: CGFloat,
                       spacing: CGFloat = 0.016) -> Path {
        var p = Path()
        guard rect.width > 0, rect.height > 0 else { return p }
        let theta = angleDegrees * .pi / 180
        let dir = CGPoint(x: sin(theta), y: cos(theta))
        let perp = CGPoint(x: cos(theta), y: -sin(theta))
        let halfSpan = (abs(rect.width * perp.x) + abs(rect.height * perp.y)) / 2
        let length = abs(rect.width * dir.x) + abs(rect.height * dir.y)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var offset = -halfSpan
        while offset <= halfSpan {
            let mid = CGPoint(x: center.x + perp.x * offset,
                              y: center.y + perp.y * offset)
            let start = CGPoint(x: mid.x - dir.x * length / 2,
                                y: mid.y - dir.y * length / 2)
            let end = CGPoint(x: mid.x + dir.x * length / 2,
                              y: mid.y + dir.y * length / 2)
            let bow = spacing * 0.9 * (1 - abs(offset) / max(halfSpan, 0.0001))
            let control = CGPoint(x: mid.x + perp.x * bow, y: mid.y + perp.y * bow)
            p.move(to: start)
            p.addQuadCurve(to: end, control: control)
            offset += spacing
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
        case .rhomboids:        return rhomboids()
        case .deltPosterior:    return deltPosterior()
        case .deltLateralBack:  return deltLateralBack()
        case .tricepsLong:      return tricepsLong()
        case .tricepsLateral:   return tricepsLateral()
        case .lats:             return lats()
        case .lowerBack:        return lowerBack()
        case .forearmBack:      return forearmBack()
        case .glutes:           return glutes()
        case .gluteMedius:      return gluteMedius()
        case .hamstringLateral: return hamstringLateral()
        case .hamstringMedial:  return hamstringMedial()
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
