import CoreImage
import UIKit
@preconcurrency import Vision

/// Lifts a packshot off its background so a food row shows the product
/// alone. The same on-device Vision mask as `TableLiftEngine`, tuned for
/// one product per photo instead of a table of dishes.
enum ProductCutoutEngine {

    /// Longest edge kept. A 56 pt thumbnail at 3x is 168 px; this leaves
    /// headroom without decoding more than a packshot holds.
    static let maxEdge: CGFloat = 384
    /// Together the instances must span this share of the photo. Less
    /// means Vision found a logo or a sticker on the pack, not the pack.
    static let minimumSpan: CGFloat = 0.2

    /// The product on a transparent canvas, cropped to its edges, or nil
    /// when the mask found nothing worth keeping. Throws when Vision could
    /// not run at all, so the caller can try again another time.
    static func cutOut(_ image: UIImage) throws -> UIImage? {
        guard let cgImage = TableLiftEngine.upright(image, maxEdge: maxEdge) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first,
              spansProduct(TableLiftEngine.instanceBoxes(in: observation.instanceMask))
        else { return nil }

        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let cut = CIContext().createCGImage(masked, from: masked.extent) else { return nil }
        return UIImage(cgImage: cut)
    }

    static func spansProduct(_ boxes: [TableLiftEngine.Box]) -> Bool {
        guard let first = boxes.first else { return false }
        let union = boxes.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        return union.width * union.height >= minimumSpan
    }
}
