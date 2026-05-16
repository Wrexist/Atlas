import SwiftUI

/// Geometric definitions for the stylized anatomical figure used by
/// `MuscleMapView`. Each muscle is a `Path` drawn in a normalized
/// `[0…1] × [0…2.4]` coordinate space (1.0 wide, 2.4 tall — the
/// roughly 8-head canonical figure ratio). The view scales these up
/// to fit whatever pixel rect it receives through `GeometryReader`.
///
/// Keeping the geometry in one place means the muscle map can be
/// re-skinned (different stroke weights, different palette, eventually
/// swap-in commissioned anatomical asset packs) without touching the
/// view layer that consumes it.
enum BodyAnatomy {

    /// Canonical aspect ratio of a single body figure (width / height).
    static let aspect: CGFloat = 1.0 / 2.4

    // MARK: - Outline (front)

    /// The silhouette outline drawn under the muscle layer to give
    /// the figure a coherent body shape. Built as a single closed
    /// path — head + neck + torso + arms + legs — so a single
    /// stroke pass renders it cleanly.
    static func frontSilhouette() -> Path {
        var p = Path()
        // Head (circle)
        p.addEllipse(in: CGRect(x: 0.36, y: 0.04, width: 0.28, height: 0.28))
        // Neck
        p.addRect(CGRect(x: 0.44, y: 0.30, width: 0.12, height: 0.08))
        // Torso (rounded rect, wider at shoulders, narrower at waist)
        p.addPath(torsoPath(top: 0.36, bottom: 1.40,
                            shoulderInset: 0.10, waistInset: 0.30))
        // Hips → upper legs taper
        p.addPath(hipsPath(top: 1.30, bottom: 1.55))
        // Legs (left + right)
        p.addPath(legPath(side: .left,  top: 1.45, bottom: 2.36))
        p.addPath(legPath(side: .right, top: 1.45, bottom: 2.36))
        // Arms (left + right)
        p.addPath(armPath(side: .left,  top: 0.40, bottom: 1.30))
        p.addPath(armPath(side: .right, top: 0.40, bottom: 1.30))
        return p
    }

    static func backSilhouette() -> Path {
        // Mirror-symmetric front view doubles for the back outline.
        // Differences (head shape from behind, scapulae) are conveyed
        // by the back-only muscle layer rather than the silhouette.
        frontSilhouette()
    }

    // MARK: - Front muscles

    static func chest() -> Path {
        var p = Path()
        // Two pectoral lobes meeting at the sternum.
        p.addPath(roundedShape(at: CGRect(x: 0.27, y: 0.46, width: 0.22, height: 0.20)))
        p.addPath(roundedShape(at: CGRect(x: 0.51, y: 0.46, width: 0.22, height: 0.20)))
        return p
    }

    static func abdominals() -> Path {
        var p = Path()
        // Rectus abdominis: stacked rounded squares for the six-pack
        // read. Three rows × two columns gives a recognisable shape
        // without requiring tendinous-inscription detail.
        for row in 0..<3 {
            let y = 0.74 + Double(row) * 0.13
            p.addPath(roundedShape(at: CGRect(x: 0.42, y: y, width: 0.08, height: 0.10)))
            p.addPath(roundedShape(at: CGRect(x: 0.50, y: y, width: 0.08, height: 0.10)))
        }
        return p
    }

    static func obliques() -> Path {
        var p = Path()
        p.addPath(slantedShape(at: CGRect(x: 0.32, y: 0.78, width: 0.10, height: 0.32),
                               leanRight: true))
        p.addPath(slantedShape(at: CGRect(x: 0.58, y: 0.78, width: 0.10, height: 0.32),
                               leanRight: false))
        return p
    }

    static func shouldersFront() -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 0.16, y: 0.38, width: 0.16, height: 0.13))
        p.addEllipse(in: CGRect(x: 0.68, y: 0.38, width: 0.16, height: 0.13))
        return p
    }

    static func neckFront() -> Path {
        roundedShape(at: CGRect(x: 0.43, y: 0.30, width: 0.14, height: 0.08))
    }

    static func bicepsLeft() -> Path {
        roundedShape(at: CGRect(x: 0.13, y: 0.50, width: 0.12, height: 0.22))
    }

    static func bicepsRight() -> Path {
        roundedShape(at: CGRect(x: 0.75, y: 0.50, width: 0.12, height: 0.22))
    }

    static func forearmsFront() -> Path {
        var p = Path()
        p.addPath(roundedShape(at: CGRect(x: 0.10, y: 0.78, width: 0.12, height: 0.40)))
        p.addPath(roundedShape(at: CGRect(x: 0.78, y: 0.78, width: 0.12, height: 0.40)))
        return p
    }

    static func quadricepsLeft() -> Path {
        roundedShape(at: CGRect(x: 0.31, y: 1.50, width: 0.16, height: 0.45))
    }

    static func quadricepsRight() -> Path {
        roundedShape(at: CGRect(x: 0.53, y: 1.50, width: 0.16, height: 0.45))
    }

    static func adductors() -> Path {
        var p = Path()
        p.addPath(roundedShape(at: CGRect(x: 0.44, y: 1.50, width: 0.06, height: 0.30)))
        p.addPath(roundedShape(at: CGRect(x: 0.50, y: 1.50, width: 0.06, height: 0.30)))
        return p
    }

    static func calvesFront() -> Path {
        var p = Path()
        p.addPath(roundedShape(at: CGRect(x: 0.32, y: 1.98, width: 0.14, height: 0.30)))
        p.addPath(roundedShape(at: CGRect(x: 0.54, y: 1.98, width: 0.14, height: 0.30)))
        return p
    }

    // MARK: - Back muscles

    static func traps() -> Path {
        // Diamond from neck to mid-back.
        var p = Path()
        p.move(to: CGPoint(x: 0.5, y: 0.36))
        p.addLine(to: CGPoint(x: 0.30, y: 0.50))
        p.addLine(to: CGPoint(x: 0.5, y: 0.62))
        p.addLine(to: CGPoint(x: 0.70, y: 0.50))
        p.closeSubpath()
        return p
    }

    static func lats() -> Path {
        // Wing shape — wider at the underarms, tapering to the waist.
        var p = Path()
        p.move(to: CGPoint(x: 0.22, y: 0.55))
        p.addQuadCurve(
            to: CGPoint(x: 0.42, y: 1.05),
            control: CGPoint(x: 0.18, y: 0.85)
        )
        p.addLine(to: CGPoint(x: 0.58, y: 1.05))
        p.addQuadCurve(
            to: CGPoint(x: 0.78, y: 0.55),
            control: CGPoint(x: 0.82, y: 0.85)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0.50, y: 0.62),
            control: CGPoint(x: 0.65, y: 0.55)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0.22, y: 0.55),
            control: CGPoint(x: 0.35, y: 0.55)
        )
        p.closeSubpath()
        return p
    }

    static func lowerBack() -> Path {
        roundedShape(at: CGRect(x: 0.40, y: 1.05, width: 0.20, height: 0.20))
    }

    static func shouldersBack() -> Path {
        // Mirror of front shoulders.
        shouldersFront()
    }

    static func tricepsLeft() -> Path {
        roundedShape(at: CGRect(x: 0.13, y: 0.52, width: 0.12, height: 0.22))
    }

    static func tricepsRight() -> Path {
        roundedShape(at: CGRect(x: 0.75, y: 0.52, width: 0.12, height: 0.22))
    }

    static func forearmsBack() -> Path {
        forearmsFront()
    }

    static func glutesLeft() -> Path {
        // Half-circle facing right.
        var p = Path()
        let rect = CGRect(x: 0.30, y: 1.30, width: 0.20, height: 0.22)
        p.addEllipse(in: rect)
        return p
    }

    static func glutesRight() -> Path {
        var p = Path()
        let rect = CGRect(x: 0.50, y: 1.30, width: 0.20, height: 0.22)
        p.addEllipse(in: rect)
        return p
    }

    static func hamstringsLeft() -> Path {
        roundedShape(at: CGRect(x: 0.31, y: 1.55, width: 0.16, height: 0.40))
    }

    static func hamstringsRight() -> Path {
        roundedShape(at: CGRect(x: 0.53, y: 1.55, width: 0.16, height: 0.40))
    }

    static func calvesBack() -> Path {
        // Calves render the same shape from front or back; the mirror
        // would only matter for ankle inflection, which we don't draw.
        calvesFront()
    }

    // MARK: - Path helpers

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

    // MARK: - Internal shape primitives

    private enum Side { case left, right }

    private static func roundedShape(at rect: CGRect, cornerRadius: CGFloat = 0.04) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }

    /// Slanted shape used for the obliques — a parallelogram that
    /// reads as a leaning slab on either side of the abs.
    private static func slantedShape(at rect: CGRect, leanRight: Bool) -> Path {
        var p = Path()
        let topShift = leanRight ? rect.width * 0.15 : -rect.width * 0.15
        let bottomShift = leanRight ? -rect.width * 0.15 : rect.width * 0.15
        p.move(to: CGPoint(x: rect.minX + topShift, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + topShift, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + bottomShift, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + bottomShift, y: rect.maxY))
        p.closeSubpath()
        return p
    }

    private static func torsoPath(top: CGFloat, bottom: CGFloat,
                                  shoulderInset: CGFloat, waistInset: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: shoulderInset, y: top))
        p.addLine(to: CGPoint(x: 1 - shoulderInset, y: top))
        p.addQuadCurve(
            to: CGPoint(x: 1 - waistInset, y: bottom),
            control: CGPoint(x: 1 - shoulderInset * 0.6, y: (top + bottom) / 2)
        )
        p.addLine(to: CGPoint(x: waistInset, y: bottom))
        p.addQuadCurve(
            to: CGPoint(x: shoulderInset, y: top),
            control: CGPoint(x: shoulderInset * 0.6, y: (top + bottom) / 2)
        )
        p.closeSubpath()
        return p
    }

    private static func hipsPath(top: CGFloat, bottom: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.30, y: top))
        p.addLine(to: CGPoint(x: 0.70, y: top))
        p.addQuadCurve(
            to: CGPoint(x: 0.65, y: bottom),
            control: CGPoint(x: 0.74, y: (top + bottom) / 2)
        )
        p.addLine(to: CGPoint(x: 0.35, y: bottom))
        p.addQuadCurve(
            to: CGPoint(x: 0.30, y: top),
            control: CGPoint(x: 0.26, y: (top + bottom) / 2)
        )
        p.closeSubpath()
        return p
    }

    private static func legPath(side: Side, top: CGFloat, bottom: CGFloat) -> Path {
        let centerX: CGFloat = side == .left ? 0.39 : 0.61
        let width: CGFloat = 0.18
        let rect = CGRect(x: centerX - width / 2, y: top, width: width, height: bottom - top)
        return Path(roundedRect: rect, cornerRadius: 0.08, style: .continuous)
    }

    private static func armPath(side: Side, top: CGFloat, bottom: CGFloat) -> Path {
        let centerX: CGFloat = side == .left ? 0.16 : 0.84
        let width: CGFloat = 0.16
        let rect = CGRect(x: centerX - width / 2, y: top, width: width, height: bottom - top)
        return Path(roundedRect: rect, cornerRadius: 0.06, style: .continuous)
    }
}
