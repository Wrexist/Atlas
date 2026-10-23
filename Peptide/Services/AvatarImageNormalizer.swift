import ImageIO
import UIKit

/// Turns a picked photo into the stored avatar: the largest centred square,
/// at most `maxPixelSize` pixels a side, JPEG-encoded. Renderers run at
/// scale 1 so the target is pixels, not points at the screen's 3x — the
/// avatar rides in the synced profile record, which has a 1 MB ceiling.
enum AvatarImageNormalizer {
    static let maxPixelSize: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.82

    /// Decodes through ImageIO's thumbnailer so a 48 MP photo is downsampled
    /// while decoding instead of becoming a full-resolution bitmap first.
    static func normalize(rawImageData data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              min(pixelWidth, pixelHeight) > 0
        else { return nil }
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)
        // The thumbnail caps the long side; size it so the short side — the
        // square that survives the crop — still reaches `maxPixelSize`.
        let longSide = max(width, height)
        let thumbnailLongSide = min(longSide, (maxPixelSize * longSide / min(width, height)).rounded(.up))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(thumbnailLongSide),
        ] as [CFString: Any] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return normalize(image: UIImage(cgImage: thumbnail))
    }

    static func normalize(image: UIImage) -> Data? {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0 else { return nil }
        let target = min(side * image.scale, maxPixelSize).rounded()
        let drawScale = target / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        // `draw(in:)` honours imageOrientation, so portrait shots aren't
        // cropped sideways.
        let square = renderer.image { _ in
            image.draw(in: CGRect(
                x: -(size.width - side) / 2 * drawScale,
                y: -(size.height - side) / 2 * drawScale,
                width: size.width * drawScale,
                height: size.height * drawScale
            ))
        }
        return square.jpegData(compressionQuality: jpegQuality)
    }
}
