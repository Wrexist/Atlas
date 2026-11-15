import SwiftUI

/// The three macronutrients, in the order every macro row lists them.
enum MacroKind: CaseIterable, Sendable {
    case protein, carbs, fat
}

/// One icon per macro, drawn instead of a "P / C / F" letter so the
/// meaning survives translation (Swedish carbs is "K") and colour
/// blindness: a drumstick for protein, a wheat ear for carbs, an avocado
/// half for fat. Drawn on a 24-point grid and scaled to the frame, so the
/// app, widgets and watch share one set. The caller supplies the colour
/// through `foregroundStyle`.
struct MacroGlyph: Shape {
    let kind: MacroKind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.grid
        let fit = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(
                translationX: rect.midX - Self.grid * scale / 2,
                y: rect.midY - Self.grid * scale / 2
            ))
        return Self.outline(of: kind).applying(fit)
    }

    private static let grid: CGFloat = 24

    private static func outline(of kind: MacroKind) -> Path {
        switch kind {
        case .protein: drumstick
        case .carbs: wheatEar
        case .fat: avocadoHalf
        }
    }

    private static var drumstick: Path {
        var meat = Path()
        meat.move(to: CGPoint(x: 9.6, y: 13.4))
        meat.addCurve(to: CGPoint(x: 11.8, y: 4.2), control1: CGPoint(x: 7.8, y: 10.6), control2: CGPoint(x: 8.6, y: 6.2))
        meat.addCurve(to: CGPoint(x: 20.8, y: 6.0), control1: CGPoint(x: 15.0, y: 2.2), control2: CGPoint(x: 19.2, y: 3.0))
        meat.addCurve(to: CGPoint(x: 17.8, y: 14.4), control1: CGPoint(x: 22.4, y: 9.0), control2: CGPoint(x: 21.0, y: 12.8))
        meat.addCurve(to: CGPoint(x: 11.0, y: 14.6), control1: CGPoint(x: 15.2, y: 15.7), control2: CGPoint(x: 12.4, y: 15.4))
        meat.closeSubpath()
        return meat
            .union(bar(centre: CGPoint(x: 8.2, y: 15.8), width: 2.9, height: 6.4, degrees: 45))
            .union(oval(centre: CGPoint(x: 7.0, y: 19.4), radiusX: 2.2, radiusY: 2.2))
            .union(oval(centre: CGPoint(x: 4.6, y: 17.0), radiusX: 2.2, radiusY: 2.2))
    }

    private static var wheatEar: Path {
        var ear = bar(centre: CGPoint(x: 12, y: 15), width: 1.5, height: 14, degrees: 0)
            .union(oval(centre: CGPoint(x: 12, y: 4.6), radiusX: 1.55, radiusY: 3))
        for y: CGFloat in [9.0, 13.6, 18.2] {
            ear = ear
                .union(oval(centre: CGPoint(x: 9.4, y: y), radiusX: 1.55, radiusY: 3, degrees: -32))
                .union(oval(centre: CGPoint(x: 14.6, y: y), radiusX: 1.55, radiusY: 3, degrees: 32))
        }
        return ear
    }

    private static var avocadoHalf: Path {
        var flesh = Path()
        flesh.move(to: CGPoint(x: 12, y: 2))
        flesh.addCurve(to: CGPoint(x: 16.4, y: 7.0), control1: CGPoint(x: 14.6, y: 2), control2: CGPoint(x: 15.6, y: 4.4))
        flesh.addCurve(to: CGPoint(x: 19.2, y: 15.0), control1: CGPoint(x: 17.0, y: 9.0), control2: CGPoint(x: 19.2, y: 11.0))
        flesh.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 19.2, y: 19.2), control2: CGPoint(x: 16.0, y: 22))
        flesh.addCurve(to: CGPoint(x: 4.8, y: 15.0), control1: CGPoint(x: 8.0, y: 22), control2: CGPoint(x: 4.8, y: 19.2))
        flesh.addCurve(to: CGPoint(x: 7.6, y: 7.0), control1: CGPoint(x: 4.8, y: 11.0), control2: CGPoint(x: 7.0, y: 9.0))
        flesh.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 8.4, y: 4.4), control2: CGPoint(x: 9.4, y: 2))
        flesh.closeSubpath()
        return flesh.subtracting(oval(centre: CGPoint(x: 12, y: 15.2), radiusX: 3.6, radiusY: 3.6))
    }

    private static func oval(centre: CGPoint, radiusX: CGFloat, radiusY: CGFloat, degrees: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: -radiusX, y: -radiusY, width: radiusX * 2, height: radiusY * 2))
            .applying(place(centre: centre, degrees: degrees))
    }

    private static func bar(centre: CGPoint, width: CGFloat, height: CGFloat, degrees: CGFloat) -> Path {
        Path(CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            .applying(place(centre: centre, degrees: degrees))
    }

    private static func place(centre: CGPoint, degrees: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: degrees * .pi / 180)
            .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
    }
}

/// A macro icon sized like the text beside it: `size` is the point size at
/// the default text size and grows with Dynamic Type.
struct MacroIcon: View {
    let kind: MacroKind
    @ScaledMetric private var side: CGFloat

    init(_ kind: MacroKind, size: CGFloat, relativeTo textStyle: Font.TextStyle = .caption) {
        self.kind = kind
        _side = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        MacroGlyph(kind: kind)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
