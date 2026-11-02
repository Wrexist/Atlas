import CoreImage
import UIKit
@preconcurrency import Vision

/// Cuts groceries out of a photo as die-cut stickers, the way the table
/// scan lifts dishes.
///
/// A packed fridge is one tangle to Vision's whole-photo mask, so each
/// product is lifted from its own box (the boxes come from the fridge
/// scan): the box is cropped with a little air, Vision separates the
/// product from the shelf behind it, and the instances nearest the middle
/// become the sticker. When Vision finds nothing, the plain crop on a
/// rounded card stands in.
///
/// Runs on-device.
enum FridgeLiftEngine {

    /// Air kept around a box, as a share of its size, so a tight box
    /// doesn't shave the pack's edges.
    static let margin: CGFloat = 0.08
    /// An instance whose centre lies this close to the crop's middle is
    /// the product; further out it is a neighbour poking in.
    static let centreReach: CGFloat = 0.35

    /// Upright pixels shared by every box of one photo.
    static func prepare(_ photo: UIImage) -> CGImage? {
        TableLiftEngine.upright(photo, maxEdge: TableLiftEngine.workingEdge)
    }

    /// One sticker per box, in order; runs off the main actor.
    static func lift(_ boxes: [CGRect], from image: CGImage) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            let context = CIContext()
            return boxes.map { sticker(for: $0, in: image, context: context) }
        }.value
    }

    /// The whole photo as one product: the "add by photo" path.
    static func liftSingle(from photo: UIImage) async -> UIImage? {
        guard let image = prepare(photo) else { return nil }
        return await lift([CGRect(x: 0, y: 0, width: 1, height: 1)], from: image).first
    }

    private static func sticker(for box: CGRect, in image: CGImage, context: CIContext) -> UIImage {
        let crop = pixelRect(expanded(box), in: image)
        guard let cropped = image.cropping(to: crop) else { return card(image) }
        return (try? masked(cropped, context: context)) ?? card(cropped)
    }

    static func expanded(_ box: CGRect) -> CGRect {
        box.insetBy(dx: -box.width * margin, dy: -box.height * margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func pixelRect(_ box: CGRect, in image: CGImage) -> CGRect {
        CGRect(
            x: box.minX * CGFloat(image.width),
            y: box.minY * CGFloat(image.height),
            width: box.width * CGFloat(image.width),
            height: box.height * CGFloat(image.height)
        ).integral
    }

    private static func masked(_ image: CGImage, context: CIContext) throws -> UIImage? {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        let central = centralInstances(TableLiftEngine.instanceBoxes(in: observation.instanceMask))
        guard !central.isEmpty else { return nil }
        let buffer = try observation.generateMaskedImage(
            ofInstances: central, from: handler, croppedToInstancesExtent: true
        )
        return TableLiftEngine.sticker(from: CIImage(cvPixelBuffer: buffer), context: context)
    }

    /// Labels of the instances centred near the crop's middle, or the
    /// largest one when none is.
    static func centralInstances(_ boxes: [TableLiftEngine.Box]) -> IndexSet {
        let centre = CGPoint(x: 0.5, y: 0.5)
        let near = boxes.filter { abs($0.frame.midX - centre.x) <= centreReach && abs($0.frame.midY - centre.y) <= centreReach }
        if !near.isEmpty { return IndexSet(near.map(\.label)) }
        guard let largest = boxes.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return []
        }
        return IndexSet(integer: largest.label)
    }

    /// The crop on a white rounded card: what a product looks like when
    /// it can't be lifted cleanly.
    private static func card(_ image: CGImage) -> UIImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let rim = max(3, min(width, height) * 0.025)
        let canvas = CGSize(width: width + rim * 2, height: height + rim * 2)
        let radius = min(width, height) * 0.12
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: radius + rim).fill()
            let inner = CGRect(x: rim, y: rim, width: width, height: height)
            renderer.cgContext.addPath(UIBezierPath(roundedRect: inner, cornerRadius: radius).cgPath)
            renderer.cgContext.clip()
            UIImage(cgImage: image).draw(in: inner)
        }
    }
}
