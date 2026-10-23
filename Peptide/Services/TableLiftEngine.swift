import CoreImage
import UIKit
@preconcurrency import Vision

/// Cuts every separate dish out of one photo of a table.
///
/// Vision's foreground-instance mask labels each object it can separate
/// from the background; each label becomes a sticker — the dish on a
/// transparent canvas with a white die-cut rim — plus the box it sat in,
/// so the review screen can fly the sticker out of the photo from exactly
/// where it was.
///
/// Runs on-device. Nothing here leaves the phone; reading each dish's
/// nutrition is `TableDishReader`'s job.
enum TableLiftEngine {

    struct Lifted: Identifiable, @unchecked Sendable {
        let id: UUID
        let sticker: UIImage
        /// Where the dish sat in the photo: 0…1, top-left origin.
        let frame: CGRect
    }

    struct Box: Equatable {
        let label: Int
        let frame: CGRect
    }

    enum Failure: LocalizedError {
        case unreadablePhoto
        case nothingFound

        var errorDescription: String? {
            switch self {
            case .unreadablePhoto: String(localized: "Couldn't read that photo. Try another one.")
            case .nothingFound:    String(localized: "Couldn't find any dishes. Shoot straight down with the whole table in frame, or cut them out yourself.")
            }
        }
    }

    /// The review grid stays readable up to here; a bigger spread is
    /// better as two photos.
    static let maxDishes = 8
    /// Share of the photo below which an instance is a chopstick, a crumb
    /// or a napkin corner rather than something anyone ate.
    static let minimumArea: CGFloat = 0.01
    /// Longest edge handed to Vision. The mask comes back far smaller than
    /// a camera frame anyway; this keeps the cut-outs sharp without
    /// decoding 48 MP for them.
    static let workingEdge: CGFloat = 2048

    static func lift(from photo: UIImage) async throws -> [Lifted] {
        guard let cgImage = upright(photo, maxEdge: workingEdge) else { throw Failure.unreadablePhoto }
        return try await Task.detached(priority: .userInitiated) {
            try cutOut(cgImage)
        }.value
    }

    private static func cutOut(_ cgImage: CGImage) throws -> [Lifted] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { throw Failure.nothingFound }

        let context = CIContext()
        let lifted = dishes(in: instanceBoxes(in: observation.instanceMask)).compactMap { box -> Lifted? in
            guard let buffer = try? observation.generateMaskedImage(
                ofInstances: IndexSet(integer: box.label),
                from: handler,
                croppedToInstancesExtent: true
            ), let sticker = sticker(from: CIImage(cvPixelBuffer: buffer), context: context) else { return nil }
            return Lifted(id: UUID(), sticker: sticker, frame: box.frame)
        }
        guard !lifted.isEmpty else { throw Failure.nothingFound }
        return lifted
    }

    // MARK: - Boxes

    static func instanceBoxes(in mask: CVPixelBuffer) -> [Box] {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let labels = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height)
        return instanceBoxes(
            labels: Array(labels),
            width: CVPixelBufferGetWidth(mask),
            height: height,
            bytesPerRow: bytesPerRow
        )
    }

    /// Bounding box of every non-zero label in a one-byte-per-pixel mask,
    /// normalised to 0…1 with a top-left origin.
    static func instanceBoxes(labels: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [Box] {
        guard width > 0, height > 0 else { return [] }
        var bounds: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = Int(labels[y * bytesPerRow + x])
                guard label != 0 else { continue }
                if let b = bounds[label] {
                    bounds[label] = (min(b.minX, x), min(b.minY, y), max(b.maxX, x), max(b.maxY, y))
                } else {
                    bounds[label] = (x, y, x, y)
                }
            }
        }
        return bounds.map { label, b in
            Box(label: label, frame: CGRect(
                x: CGFloat(b.minX) / CGFloat(width),
                y: CGFloat(b.minY) / CGFloat(height),
                width: CGFloat(b.maxX - b.minX + 1) / CGFloat(width),
                height: CGFloat(b.maxY - b.minY + 1) / CGFloat(height)
            ))
        }
    }

    /// Drops the crumbs, caps the count, and orders what is left the way
    /// the table reads: top row first, left to right, so the grid lands
    /// in roughly the layout the user just photographed.
    static func dishes(in boxes: [Box]) -> [Box] {
        let rowHeight: CGFloat = 0.25
        let kept = boxes
            .filter { $0.frame.width * $0.frame.height >= minimumArea }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .prefix(maxDishes)
        return kept.sorted { lhs, rhs in
            let lhsRow = Int(lhs.frame.midY / rowHeight)
            let rhsRow = Int(rhs.frame.midY / rowHeight)
            return lhsRow != rhsRow ? lhsRow < rhsRow : lhs.frame.midX < rhs.frame.midX
        }
    }

    // MARK: - Stickers

    /// The cut-out on a canvas padded for a white die-cut rim: the alpha
    /// is dilated, painted white, and the dish laid back on top.
    private static func sticker(from cutout: CIImage, context: CIContext) -> UIImage? {
        let extent = cutout.extent
        let rim = max(3, min(extent.width, extent.height) * 0.025)
        let canvas = extent.insetBy(dx: -rim * 2, dy: -rim * 2)
        let padded = cutout.composited(over: CIImage(color: .clear).cropped(to: canvas))
        let outline = padded
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: rim])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
            ])
        let composed = padded.composited(over: outline).cropped(to: canvas)
        guard let cgImage = context.createCGImage(composed, from: canvas) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// A circular cut taken by hand, for the dish Vision missed. `circle`
    /// is normalised to the photo like `Lifted.frame`.
    static func cut(_ circle: CGRect, from photo: UIImage) -> Lifted? {
        guard let cgImage = upright(photo, maxEdge: workingEdge) else { return nil }
        let pixels = CGRect(
            x: circle.minX * CGFloat(cgImage.width),
            y: circle.minY * CGFloat(cgImage.height),
            width: circle.width * CGFloat(cgImage.width),
            height: circle.height * CGFloat(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: pixels) else { return nil }
        let side = CGFloat(min(cropped.width, cropped.height))
        let rim = max(3, side * 0.025)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let canvas = CGSize(width: side + rim * 2, height: side + rim * 2)
        let sticker = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let plate = CGRect(x: rim, y: rim, width: side, height: side)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: canvas)).fill()
            renderer.cgContext.addEllipse(in: plate)
            renderer.cgContext.clip()
            // Centred at its own aspect: at a photo edge the crop is not square.
            let width = CGFloat(cropped.width)
            let height = CGFloat(cropped.height)
            UIImage(cgImage: cropped).draw(in: CGRect(
                x: rim + (side - width) / 2, y: rim + (side - height) / 2, width: width, height: height
            ))
        }
        return Lifted(id: UUID(), sticker: sticker, frame: circle)
    }

    /// Bakes the photo's orientation into its pixels and caps its size,
    /// so the mask, the boxes and the drawn photo all share one frame.
    static func upright(_ image: UIImage, maxEdge: CGFloat) -> CGImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > 0 else { return nil }
        let ratio = min(1, maxEdge / longest)
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
