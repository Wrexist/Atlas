import SwiftUI

/// Geometric definitions for the anatomical figure used by
/// `MuscleMapView`. Each muscle is a `Path` drawn in a normalized
/// `[0…1] × [0…2.4]` coordinate space (1.0 wide, 2.4 tall — the
/// roughly 8-head canonical figure ratio). The view scales these up
/// to fit whatever pixel rect it receives through `GeometryReader`.
///
/// The shapes are hand-built from smooth Bézier curves rather than
/// rounded rectangles so the body reads as real anatomy — fanned
/// pectorals, capped deltoids, spindle biceps, teardrop quads,
/// winged lats. Left/right pairs are derived from a single drawn
/// side through `mirror`, so the figure is always perfectly
/// symmetric. A faint `skeleton` layer (skull, ribcage, spine,
/// pelvis, long bones, joints) sits under the muscles to ground the
/// figure as an anatomical chart.
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

    /// One smooth, continuous humanoid outline — head, neck, shoulders,
    /// arms (with armpit notches), tapered torso, hips, and legs. Built
    /// by tracing the right half from crown to crotch, then mirroring
    /// that trace back up the left half, so the two sides match exactly.
    static func frontSilhouette() -> Path {
        symmetricBody(
            top: CGPoint(x: 0.50, y: 0.040),
            rightSide: [
                // Crown → right temple
                Cubic(to: CGPoint(x: 0.610, y: 0.150), c1: CGPoint(x: 0.582, y: 0.040), c2: CGPoint(x: 0.610, y: 0.090)),
                // Temple → jaw
                Cubic(to: CGPoint(x: 0.556, y: 0.300), c1: CGPoint(x: 0.610, y: 0.225), c2: CGPoint(x: 0.598, y: 0.272)),
                // Jaw → base of neck
                Cubic(to: CGPoint(x: 0.560, y: 0.355), c1: CGPoint(x: 0.556, y: 0.322), c2: CGPoint(x: 0.558, y: 0.338)),
                // Trapezius / clavicle slope → outer deltoid
                Cubic(to: CGPoint(x: 0.826, y: 0.476), c1: CGPoint(x: 0.648, y: 0.382), c2: CGPoint(x: 0.762, y: 0.420)),
                // Deltoid cap → upper arm
                Cubic(to: CGPoint(x: 0.872, y: 0.660), c1: CGPoint(x: 0.884, y: 0.524), c2: CGPoint(x: 0.886, y: 0.592)),
                // Upper arm → elbow
                Cubic(to: CGPoint(x: 0.858, y: 0.952), c1: CGPoint(x: 0.876, y: 0.770), c2: CGPoint(x: 0.870, y: 0.876)),
                // Forearm → outer wrist
                Cubic(to: CGPoint(x: 0.832, y: 1.298), c1: CGPoint(x: 0.858, y: 1.090), c2: CGPoint(x: 0.848, y: 1.220)),
                // Around the wrist → inner wrist
                Cubic(to: CGPoint(x: 0.792, y: 1.302), c1: CGPoint(x: 0.826, y: 1.330), c2: CGPoint(x: 0.812, y: 1.330)),
                // Inner arm up → armpit
                Cubic(to: CGPoint(x: 0.662, y: 0.566), c1: CGPoint(x: 0.762, y: 1.030), c2: CGPoint(x: 0.694, y: 0.648)),
                // Lat / ribs down → waist
                Cubic(to: CGPoint(x: 0.634, y: 1.010), c1: CGPoint(x: 0.672, y: 0.762), c2: CGPoint(x: 0.642, y: 0.884)),
                // Waist → hip
                Cubic(to: CGPoint(x: 0.690, y: 1.298), c1: CGPoint(x: 0.642, y: 1.150), c2: CGPoint(x: 0.684, y: 1.232)),
                // Hip / outer thigh → knee
                Cubic(to: CGPoint(x: 0.628, y: 1.842), c1: CGPoint(x: 0.706, y: 1.470), c2: CGPoint(x: 0.660, y: 1.700)),
                // Knee → outer calf
                Cubic(to: CGPoint(x: 0.602, y: 2.066), c1: CGPoint(x: 0.628, y: 1.934), c2: CGPoint(x: 0.626, y: 1.988)),
                // Calf → outer ankle
                Cubic(to: CGPoint(x: 0.548, y: 2.318), c1: CGPoint(x: 0.586, y: 2.182), c2: CGPoint(x: 0.566, y: 2.278)),
                // Across the foot → inner ankle
                Cubic(to: CGPoint(x: 0.520, y: 2.324), c1: CGPoint(x: 0.540, y: 2.336), c2: CGPoint(x: 0.530, y: 2.336)),
                // Inner lower leg up → inner knee
                Cubic(to: CGPoint(x: 0.514, y: 1.872), c1: CGPoint(x: 0.522, y: 2.150), c2: CGPoint(x: 0.514, y: 1.984)),
                // Inner thigh up → crotch (centre line)
                Cubic(to: CGPoint(x: 0.500, y: 1.432), c1: CGPoint(x: 0.514, y: 1.702), c2: CGPoint(x: 0.506, y: 1.520)),
            ]
        )
    }

    /// The back outline matches the front silhouette; the back-only
    /// muscle + skeleton layers convey the difference in view.
    static func backSilhouette() -> Path { frontSilhouette() }

    // MARK: - Front muscles

    static func chest() -> Path {
        // Two fanned pectoral shields meeting at the sternum, swept up
        // toward the deltoid and rounded along the lower border.
        let left = pecLobe()
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    private static func pecLobe() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.487, y: 0.452))            // sternum, top
        p.addCurve(to: CGPoint(x: 0.276, y: 0.498),         // outer-top, under delt
                   control1: CGPoint(x: 0.392, y: 0.444),
                   control2: CGPoint(x: 0.312, y: 0.456))
        p.addCurve(to: CGPoint(x: 0.318, y: 0.642),         // lower-outer border
                   control1: CGPoint(x: 0.250, y: 0.556),
                   control2: CGPoint(x: 0.268, y: 0.616))
        p.addCurve(to: CGPoint(x: 0.487, y: 0.628),         // sternum, bottom
                   control1: CGPoint(x: 0.380, y: 0.664),
                   control2: CGPoint(x: 0.440, y: 0.652))
        p.addCurve(to: CGPoint(x: 0.487, y: 0.452),         // up the sternum
                   control1: CGPoint(x: 0.487, y: 0.566),
                   control2: CGPoint(x: 0.487, y: 0.500))
        p.closeSubpath()
        return p
    }

    static func abdominals() -> Path {
        // Rectus abdominis: a 4×2 grid of softly-rounded cells split by
        // the linea alba, narrowing toward the navel.
        var p = Path()
        let rows = 4
        for row in 0..<rows {
            let y = 0.706 + Double(row) * 0.092
            // Lower cells tuck in slightly for a tapered six-pack read.
            let inset = 0.004 * Double(row)
            let w = 0.066 - inset
            p.addPath(roundedShape(at: CGRect(x: 0.432 + inset, y: y, width: w, height: 0.078),
                                   cornerRadius: 0.018))
            p.addPath(roundedShape(at: CGRect(x: 0.502, y: y, width: w, height: 0.078),
                                   cornerRadius: 0.018))
        }
        return p
    }

    static func obliques() -> Path {
        let left = slantedShape(at: CGRect(x: 0.348, y: 0.724, width: 0.082, height: 0.330),
                                leanRight: true)
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    static func shouldersFront() -> Path {
        let left = deltoidCap()
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    private static func deltoidCap() -> Path {
        // Rounded cap that wraps the shoulder joint — wide over the top,
        // tapering to a point where it meets the biceps.
        var p = Path()
        p.move(to: CGPoint(x: 0.312, y: 0.432))             // inner, at trap junction
        p.addCurve(to: CGPoint(x: 0.158, y: 0.500),         // over the top, outer
                   control1: CGPoint(x: 0.244, y: 0.404),
                   control2: CGPoint(x: 0.184, y: 0.436))
        p.addCurve(to: CGPoint(x: 0.236, y: 0.586),         // lower outer
                   control1: CGPoint(x: 0.142, y: 0.548),
                   control2: CGPoint(x: 0.178, y: 0.582))
        p.addCurve(to: CGPoint(x: 0.312, y: 0.432),         // back up to the junction
                   control1: CGPoint(x: 0.296, y: 0.560),
                   control2: CGPoint(x: 0.318, y: 0.486))
        p.closeSubpath()
        return p
    }

    static func neckFront() -> Path {
        // Sternocleidomastoid pair — two soft straps converging from the
        // jaw to the sternal notch.
        let left = spindle(center: CGPoint(x: 0.470, y: 0.345), width: 0.034, height: 0.090)
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    static func bicepsLeft() -> Path {
        spindle(center: CGPoint(x: 0.156, y: 0.612), width: 0.078, height: 0.250)
    }

    static func bicepsRight() -> Path { bicepsLeft().applying(mirror) }

    static func forearmsFront() -> Path {
        let left = limbTaper(top: CGPoint(x: 0.148, y: 0.760), topWidth: 0.092,
                             bottom: CGPoint(x: 0.130, y: 1.180), bottomWidth: 0.046)
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    static func quadricepsLeft() -> Path {
        // Teardrop quad with an outer (vastus lateralis) sweep, tapering
        // to the knee.
        var p = Path()
        p.move(to: CGPoint(x: 0.404, y: 1.476))             // inner top
        p.addCurve(to: CGPoint(x: 0.470, y: 1.500),         // top, under hip
                   control1: CGPoint(x: 0.430, y: 1.470),
                   control2: CGPoint(x: 0.452, y: 1.482))
        p.addCurve(to: CGPoint(x: 0.446, y: 1.880),         // down to inner knee
                   control1: CGPoint(x: 0.476, y: 1.640),
                   control2: CGPoint(x: 0.458, y: 1.780))
        p.addCurve(to: CGPoint(x: 0.336, y: 1.860),         // across the knee
                   control1: CGPoint(x: 0.410, y: 1.912),
                   control2: CGPoint(x: 0.366, y: 1.904))
        p.addCurve(to: CGPoint(x: 0.348, y: 1.560),         // up the outer sweep
                   control1: CGPoint(x: 0.318, y: 1.730),
                   control2: CGPoint(x: 0.322, y: 1.640))
        p.addCurve(to: CGPoint(x: 0.404, y: 1.476),         // back to inner top
                   control1: CGPoint(x: 0.362, y: 1.512),
                   control2: CGPoint(x: 0.380, y: 1.484))
        p.closeSubpath()
        return p
    }

    static func quadricepsRight() -> Path { quadricepsLeft().applying(mirror) }

    static func adductors() -> Path {
        // Inner-thigh straps on each side of the mid-line.
        let left = limbTaper(top: CGPoint(x: 0.470, y: 1.486), topWidth: 0.044,
                             bottom: CGPoint(x: 0.484, y: 1.790), bottomWidth: 0.028)
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    static func calvesFront() -> Path {
        let left = calfBelly(centerX: 0.392)
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    // MARK: - Back muscles

    static func traps() -> Path {
        // Kite from the neck, flaring over the shoulders, tapering down
        // the spine — softened with curves rather than straight edges.
        var p = Path()
        p.move(to: CGPoint(x: 0.500, y: 0.352))
        p.addCurve(to: CGPoint(x: 0.300, y: 0.512),
                   control1: CGPoint(x: 0.408, y: 0.372),
                   control2: CGPoint(x: 0.336, y: 0.444))
        p.addCurve(to: CGPoint(x: 0.500, y: 0.690),
                   control1: CGPoint(x: 0.392, y: 0.566),
                   control2: CGPoint(x: 0.452, y: 0.628))
        p.addCurve(to: CGPoint(x: 0.700, y: 0.512),
                   control1: CGPoint(x: 0.548, y: 0.628),
                   control2: CGPoint(x: 0.608, y: 0.566))
        p.addCurve(to: CGPoint(x: 0.500, y: 0.352),
                   control1: CGPoint(x: 0.664, y: 0.444),
                   control2: CGPoint(x: 0.592, y: 0.372))
        p.closeSubpath()
        return p
    }

    static func lats() -> Path {
        let left = latWing()
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    private static func latWing() -> Path {
        // Wing — broad under the armpit, sweeping in to the waist along
        // the spine.
        var p = Path()
        p.move(to: CGPoint(x: 0.300, y: 0.560))             // top, under rear delt
        p.addCurve(to: CGPoint(x: 0.456, y: 1.040),         // taper to waist (spine)
                   control1: CGPoint(x: 0.244, y: 0.760),
                   control2: CGPoint(x: 0.392, y: 0.940))
        p.addCurve(to: CGPoint(x: 0.486, y: 0.700),         // up the spine line
                   control1: CGPoint(x: 0.482, y: 0.900),
                   control2: CGPoint(x: 0.486, y: 0.800))
        p.addCurve(to: CGPoint(x: 0.300, y: 0.560),         // back to the armpit
                   control1: CGPoint(x: 0.486, y: 0.628),
                   control2: CGPoint(x: 0.392, y: 0.572))
        p.closeSubpath()
        return p
    }

    static func lowerBack() -> Path {
        // Erector / lumbar mass — a rounded shield over the lower spine.
        roundedShape(at: CGRect(x: 0.418, y: 1.030, width: 0.164, height: 0.210),
                     cornerRadius: 0.06)
    }

    static func shouldersBack() -> Path { shouldersFront() }

    static func tricepsLeft() -> Path {
        spindle(center: CGPoint(x: 0.156, y: 0.636), width: 0.080, height: 0.260)
    }

    static func tricepsRight() -> Path { tricepsLeft().applying(mirror) }

    static func forearmsBack() -> Path { forearmsFront() }

    static func glutesLeft() -> Path {
        // Rounded buttock that tucks toward the mid-line at the top.
        var p = Path()
        p.move(to: CGPoint(x: 0.498, y: 1.286))
        p.addCurve(to: CGPoint(x: 0.498, y: 1.516),
                   control1: CGPoint(x: 0.498, y: 1.400),
                   control2: CGPoint(x: 0.498, y: 1.470))
        p.addCurve(to: CGPoint(x: 0.330, y: 1.452),
                   control1: CGPoint(x: 0.420, y: 1.540),
                   control2: CGPoint(x: 0.356, y: 1.520))
        p.addCurve(to: CGPoint(x: 0.498, y: 1.286),
                   control1: CGPoint(x: 0.306, y: 1.376),
                   control2: CGPoint(x: 0.392, y: 1.296))
        p.closeSubpath()
        return p
    }

    static func glutesRight() -> Path { glutesLeft().applying(mirror) }

    static func hamstringsLeft() -> Path {
        limbTaper(top: CGPoint(x: 0.392, y: 1.540), topWidth: 0.140,
                  bottom: CGPoint(x: 0.392, y: 1.900), bottomWidth: 0.092)
    }

    static func hamstringsRight() -> Path { hamstringsLeft().applying(mirror) }

    static func calvesBack() -> Path {
        let left = calfBelly(centerX: 0.392)
        var p = left
        p.addPath(left.applying(mirror))
        return p
    }

    // MARK: - Skeleton underlay

    /// Faint skeletal scaffold drawn behind the muscles to ground the
    /// figure as an anatomy chart: skull, spine, ribcage, pelvis, the
    /// long bones, and ring joints. Returned as one strokable path.
    static func skeleton(facing front: Bool) -> Path {
        var p = Path()

        // Skull
        p.addEllipse(in: CGRect(x: 0.428, y: 0.070, width: 0.144, height: 0.196))
        // Jaw line
        p.move(to: CGPoint(x: 0.452, y: 0.250))
        p.addQuadCurve(to: CGPoint(x: 0.548, y: 0.250), control: CGPoint(x: 0.500, y: 0.300))

        // Cervical → lumbar spine
        p.move(to: CGPoint(x: 0.500, y: 0.300))
        p.addLine(to: CGPoint(x: 0.500, y: 1.300))

        // Clavicles
        p.move(to: CGPoint(x: 0.500, y: 0.430))
        p.addLine(to: CGPoint(x: 0.300, y: 0.470))
        p.move(to: CGPoint(x: 0.500, y: 0.430))
        p.addLine(to: CGPoint(x: 0.700, y: 0.470))

        // Ribcage — a tapered cage of paired arcs
        for i in 0..<4 {
            let y = 0.500 + Double(i) * 0.066
            let halfW = 0.150 - Double(i) * 0.018
            p.move(to: CGPoint(x: 0.500, y: y))
            p.addQuadCurve(to: CGPoint(x: 0.500 - halfW, y: y + 0.030),
                           control: CGPoint(x: 0.500 - halfW, y: y - 0.020))
            p.move(to: CGPoint(x: 0.500, y: y))
            p.addQuadCurve(to: CGPoint(x: 0.500 + halfW, y: y + 0.030),
                           control: CGPoint(x: 0.500 + halfW, y: y - 0.020))
        }

        // Pelvis
        p.addEllipse(in: CGRect(x: 0.372, y: 1.220, width: 0.256, height: 0.180))

        // Long bones — humerus + forearm, femur + tibia (each side)
        for s in [CGFloat(1), CGFloat(-1)] {
            func x(_ v: CGFloat) -> CGFloat { 0.5 + s * (v - 0.5) }
            // Arm
            p.move(to: CGPoint(x: x(0.760), y: 0.500))
            p.addLine(to: CGPoint(x: x(0.842), y: 0.940))      // humerus
            p.addLine(to: CGPoint(x: x(0.812), y: 1.290))      // ulna/radius
            // Leg
            p.move(to: CGPoint(x: x(0.560), y: 1.360))
            p.addLine(to: CGPoint(x: x(0.560), y: 1.850))      // femur
            p.addLine(to: CGPoint(x: x(0.556), y: 2.300))      // tibia
        }

        // Joint rings — shoulders, elbows, wrists, hips, knees, ankles
        let joints: [(CGFloat, CGFloat)] = [
            (0.760, 0.500), (0.240, 0.500),   // shoulders
            (0.842, 0.940), (0.158, 0.940),   // elbows
            (0.812, 1.290), (0.188, 1.290),   // wrists
            (0.560, 1.360), (0.440, 1.360),   // hips
            (0.560, 1.850), (0.440, 1.850),   // knees
            (0.556, 2.300), (0.444, 2.300),   // ankles
        ]
        for (jx, jy) in joints {
            p.addEllipse(in: CGRect(x: jx - 0.018, y: jy - 0.018, width: 0.036, height: 0.036))
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

    /// One cubic Bézier segment: its end point and two control points.
    private struct Cubic {
        let to: CGPoint
        let c1: CGPoint
        let c2: CGPoint
    }

    /// Builds a closed, vertically-symmetric outline. `rightSide` traces
    /// from `top` down the right half to a point on the mid-line; the
    /// left half is the mirror of that trace, walked back up, so the
    /// two halves match exactly.
    private static func symmetricBody(top: CGPoint, rightSide: [Cubic]) -> Path {
        var p = Path()
        p.move(to: top)
        for seg in rightSide {
            p.addCurve(to: seg.to, control1: seg.c1, control2: seg.c2)
        }
        // Start points of each right-side segment, for the reversed walk.
        var starts: [CGPoint] = [top]
        for seg in rightSide.dropLast() { starts.append(seg.to) }
        for i in stride(from: rightSide.count - 1, through: 0, by: -1) {
            let seg = rightSide[i]
            // Reversed cubic: swap the control points and mirror them.
            p.addCurve(to: starts[i].applying(mirror),
                       control1: seg.c2.applying(mirror),
                       control2: seg.c1.applying(mirror))
        }
        p.closeSubpath()
        return p
    }

    private static func roundedShape(at rect: CGRect, cornerRadius: CGFloat = 0.04) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }

    /// Vertical lens / spindle — the belly of a long muscle (biceps,
    /// triceps, neck strap). Widest in the middle, tapering to points.
    private static func spindle(center: CGPoint, width: CGFloat, height: CGFloat) -> Path {
        let hw = width / 2, hh = height / 2
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - hh))
        p.addCurve(to: CGPoint(x: center.x, y: center.y + hh),
                   control1: CGPoint(x: center.x + hw, y: center.y - hh * 0.3),
                   control2: CGPoint(x: center.x + hw, y: center.y + hh * 0.3))
        p.addCurve(to: CGPoint(x: center.x, y: center.y - hh),
                   control1: CGPoint(x: center.x - hw, y: center.y + hh * 0.3),
                   control2: CGPoint(x: center.x - hw, y: center.y - hh * 0.3))
        p.closeSubpath()
        return p
    }

    /// Tapered limb segment — a rounded trapezoid that's wider at the
    /// top than the bottom (forearm, hamstring, adductor).
    private static func limbTaper(top: CGPoint, topWidth: CGFloat,
                                  bottom: CGPoint, bottomWidth: CGFloat) -> Path {
        let tw = topWidth / 2, bw = bottomWidth / 2
        var p = Path()
        p.move(to: CGPoint(x: top.x - tw, y: top.y))
        p.addQuadCurve(to: CGPoint(x: top.x + tw, y: top.y),
                       control: CGPoint(x: top.x, y: top.y - 0.03))
        p.addCurve(to: CGPoint(x: bottom.x + bw, y: bottom.y),
                   control1: CGPoint(x: top.x + tw, y: (top.y + bottom.y) / 2),
                   control2: CGPoint(x: bottom.x + bw, y: (top.y + bottom.y) / 2))
        p.addQuadCurve(to: CGPoint(x: bottom.x - bw, y: bottom.y),
                       control: CGPoint(x: bottom.x, y: bottom.y + 0.03))
        p.addCurve(to: CGPoint(x: top.x - tw, y: top.y),
                   control1: CGPoint(x: bottom.x - bw, y: (top.y + bottom.y) / 2),
                   control2: CGPoint(x: top.x - tw, y: (top.y + bottom.y) / 2))
        p.closeSubpath()
        return p
    }

    /// Gastrocnemius — two stacked bulges (medial higher than lateral)
    /// for a recognisable calf read.
    private static func calfBelly(centerX: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: centerX, y: 1.950))
        p.addCurve(to: CGPoint(x: centerX + 0.064, y: 2.110),
                   control1: CGPoint(x: centerX + 0.060, y: 1.992),
                   control2: CGPoint(x: centerX + 0.070, y: 2.050))
        p.addCurve(to: CGPoint(x: centerX, y: 2.250),
                   control1: CGPoint(x: centerX + 0.052, y: 2.180),
                   control2: CGPoint(x: centerX + 0.028, y: 2.230))
        p.addCurve(to: CGPoint(x: centerX - 0.066, y: 2.090),
                   control1: CGPoint(x: centerX - 0.030, y: 2.230),
                   control2: CGPoint(x: centerX - 0.058, y: 2.170))
        p.addCurve(to: CGPoint(x: centerX, y: 1.950),
                   control1: CGPoint(x: centerX - 0.072, y: 2.030),
                   control2: CGPoint(x: centerX - 0.060, y: 1.984))
        p.closeSubpath()
        return p
    }

    /// Slanted parallelogram with rounded feel — used for the obliques.
    private static func slantedShape(at rect: CGRect, leanRight: Bool) -> Path {
        var p = Path()
        let topShift = leanRight ? rect.width * 0.18 : -rect.width * 0.18
        let bottomShift = leanRight ? -rect.width * 0.18 : rect.width * 0.18
        p.move(to: CGPoint(x: rect.minX + topShift, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + topShift, y: rect.minY),
                       control: CGPoint(x: rect.midX + topShift, y: rect.minY - 0.02))
        p.addLine(to: CGPoint(x: rect.maxX + bottomShift, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + bottomShift, y: rect.maxY),
                       control: CGPoint(x: rect.midX + bottomShift, y: rect.maxY + 0.02))
        p.closeSubpath()
        return p
    }
}
