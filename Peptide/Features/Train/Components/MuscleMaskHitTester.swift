import SwiftUI

#if canImport(UIKit)
import UIKit

/// Hit-tests taps against the baked per-muscle alpha masks so a tap lands
/// on the real muscle silhouette of the photoreal pack — not a bounding
/// box or the legacy vector paths, which don't match the Z-Anatomy render.
///
/// Each mask is sampled once into a small alpha grid (cached for the app's
/// lifetime; the masks never change), so repeated taps are cheap.
enum MuscleMaskHitTester {

    /// Low-res alpha sample of one mask plus its coverage (lit-pixel count),
    /// used to prefer the most specific muscle when masks overlap.
    private struct Grid {
        let width: Int
        let height: Int
        let alpha: [UInt8]
        let coverage: Int
    }

    private static let gridWidth = 150
    private static let gridHeight = 360
    private static var cache: [String: Grid] = [:]

    private static func grid(for name: String) -> Grid? {
        if let g = cache[name] { return g }
        guard let cg = UIImage(named: name)?.cgImage else { return nil }
        let w = gridWidth, h = gridHeight
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var alpha = [UInt8](repeating: 0, count: w * h)
        var coverage = 0
        for i in 0..<(w * h) {
            let a = buf[i * 4 + 3]
            alpha[i] = a
            if a >= 128 { coverage += 1 }
        }
        let g = Grid(width: w, height: h, alpha: alpha, coverage: coverage)
        cache[name] = g
        return g
    }

    /// Returns the mask name hit at a point normalized to the image content
    /// rect (`x`,`y` in 0…1, y measured top-down). When several masks
    /// overlap the point, the one with the smallest coverage wins so taps
    /// resolve to the most specific head (e.g. the side delt over the arm).
    static func hit(among names: [String], atNormalized p: CGPoint,
                    threshold: UInt8 = 110) -> String? {
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        var best: String?
        var bestCoverage = Int.max
        for name in names {
            guard let g = grid(for: name), g.coverage > 0 else { continue }
            let x = min(g.width - 1, max(0, Int(p.x * CGFloat(g.width))))
            // CGContext y-origin is bottom-left; the tap is top-down.
            let y = min(g.height - 1, max(0, Int((1 - p.y) * CGFloat(g.height))))
            if g.alpha[y * g.width + x] >= threshold, g.coverage < bestCoverage {
                best = name
                bestCoverage = g.coverage
            }
        }
        return best
    }
}
#endif
