import SwiftUI
import UIKit

/// Layout math shared by the photo card, the dissolve and the flying
/// cut-outs, so all three agree on where a dish sat.
enum TableStageLayout {
    /// The rect an image of `imageSize` fills inside `bounds` with
    /// `.scaledToFill()` — centred, overflowing on one axis.
    static func aspectFill(_ imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: bounds) }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// A 0…1 frame inside the photo, placed on the card.
    static func place(_ frame: CGRect, photo: CGSize, card: CGSize) -> CGRect {
        let fill = aspectFill(photo, in: card)
        return CGRect(
            x: fill.minX + frame.minX * fill.width,
            y: fill.minY + frame.minY * fill.height,
            width: frame.width * fill.width,
            height: frame.height * fill.height
        )
    }
}

/// The table photo breaking into square pixels that drift up and away,
/// the moment the dishes have been lifted off it.
///
/// Before `startedAt` it is simply the photo. After it, the photo hands
/// over to a mosaic of its own colours within a few frames, and each tile
/// then leaves on its own delay. Purely decorative: the host skips it
/// under Reduce Motion and removes it once `duration` has passed.
struct PixelDissolve: View {
    let image: UIImage
    let startedAt: Date?

    static let duration: Duration = .milliseconds(1_200)
    private static let handOver: Double = 0.15
    private static let tileLife: Double = 0.7

    @State private var tiles: [PixelTile] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: startedAt == nil)) { timeline in
            Canvas { context, size in
                let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                let fill = TableStageLayout.aspectFill(image.size, in: size)
                context.clip(to: Path(CGRect(origin: .zero, size: size)))

                let photoOpacity = tiles.isEmpty ? 1 : max(0, 1 - elapsed / Self.handOver)
                if photoOpacity > 0 {
                    var photo = context
                    photo.opacity = photoOpacity
                    photo.draw(Image(uiImage: image), in: fill)
                }
                guard elapsed > 0 else { return }

                for tile in tiles {
                    let life = min(1, max(0, (elapsed - tile.delay) / Self.tileLife))
                    guard life < 1 else { continue }
                    let eased = life * life
                    let side = tile.rect.width * fill.width * (1 - 0.6 * eased)
                    let rect = CGRect(
                        x: fill.minX + tile.rect.midX * fill.width + tile.drift.width * eased - side / 2,
                        y: fill.minY + tile.rect.midY * fill.height + tile.drift.height * eased - side / 2,
                        width: side,
                        height: side
                    )
                    var shard = context
                    shard.opacity = 1 - eased
                    shard.fill(Path(rect), with: .color(tile.color))
                }
            }
        }
        .task { tiles = await PixelTile.sample(image) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One square of the dissolving photo.
private struct PixelTile: Sendable {
    /// 0…1 within the photo.
    let rect: CGRect
    let color: Color
    let delay: Double
    let drift: CGSize

    /// Tiles across the photo's short edge.
    private static let columns = 30
    private static let maxDelay: Double = 0.45

    /// Samples the photo down to one colour per tile, off the main actor.
    static func sample(_ image: UIImage) async -> [PixelTile] {
        guard let cgImage = TableLiftEngine.upright(image, maxEdge: 512) else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [PixelTile] in
            let aspect = Double(cgImage.height) / Double(max(cgImage.width, 1))
            let cols = aspect >= 1 ? columns : max(1, Int((Double(columns) / aspect).rounded()))
            let rows = max(1, Int((Double(cols) * aspect).rounded()))
            var pixels = [UInt8](repeating: 0, count: cols * rows * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: cols, height: rows, bitsPerComponent: 8,
                    bytesPerRow: cols * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.interpolationQuality = .medium
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cols, height: rows))
                return true
            }
            guard drawn else { return [] }

            var generator = SystemRandomNumberGenerator()
            var tiles: [PixelTile] = []
            tiles.reserveCapacity(cols * rows)
            for row in 0..<rows {
                for col in 0..<cols {
                    let offset = (row * cols + col) * 4
                    let color = Color(
                        red: Double(pixels[offset]) / 255,
                        green: Double(pixels[offset + 1]) / 255,
                        blue: Double(pixels[offset + 2]) / 255
                    )
                    tiles.append(PixelTile(
                        rect: CGRect(
                            x: Double(col) / Double(cols), y: Double(row) / Double(rows),
                            width: 1 / Double(cols), height: 1 / Double(rows)
                        ),
                        color: color,
                        delay: Double.random(in: 0...maxDelay, using: &generator),
                        drift: CGSize(
                            width: Double.random(in: -24...64, using: &generator),
                            height: Double.random(in: -96 ... -12, using: &generator)
                        )
                    ))
                }
            }
            return tiles
        }.value
    }
}
