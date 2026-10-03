import SwiftUI

/// Versioned illustration geometry. The SAME path clips color and handles taps.
/// Coordinates are authored against the unmodified 1024 x 1536 source artwork.
enum TrainingAnatomy {
    static let aspect: CGFloat = 2.0 / 3.0
    static let front = "atlas_body_front"
    static let back = "atlas_body_back"
    static let regions: [String: [[Double]]] = {
        guard let url = Bundle.main.url(forResource: "anatomy-regions-v2", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: [[Double]]].self, from: data)
        else { return [:] }
        return result
    }()

    static let isAvailable: Bool = {
        #if canImport(UIKit)
        return UIImage(named: front) != nil && UIImage(named: back) != nil
            && AnatomicalMuscle.allCases.allSatisfy { regions[$0.rawValue] != nil }
        #else
        return false
        #endif
    }()

    static func path(for muscle: AnatomicalMuscle, in rect: CGRect) -> Path {
        guard let coordinates = regions[muscle.rawValue], coordinates.count >= 3 else { return Path() }
        var path = Path()
        for mirrored in [false, true] {
            let points = coordinates.compactMap { pair -> CGPoint? in
                guard pair.count == 2 else { return nil }
                let x = pair[0] / 1024
                return CGPoint(x: rect.minX + (mirrored ? 1 - x : x) * rect.width,
                               y: rect.minY + pair[1] / 1536 * rect.height)
            }
            guard points.count >= 3 else { continue }
            func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            }
            path.move(to: midpoint(points[points.count - 1], points[0]))
            for index in points.indices {
                path.addQuadCurve(to: midpoint(points[index], points[(index + 1) % points.count]),
                                  control: points[index])
            }
            path.closeSubpath()
        }
        return path
    }
}

struct TrainingMuscleShape: Shape {
    let muscle: AnatomicalMuscle
    func path(in rect: CGRect) -> Path { TrainingAnatomy.path(for: muscle, in: rect) }
}
