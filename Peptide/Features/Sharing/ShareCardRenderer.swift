import SwiftUI
import UIKit

/// Renders a `CycleCardView` to a 1080×1920 PNG file in the temporary
/// directory. The watermark is part of the same view tree, so a single
/// `ImageRenderer` pass produces one composited image — there is no
/// detachable layer for the brand mark.
@MainActor
enum ShareCardRenderer {
    enum Failure: LocalizedError {
        case render
        case encoding
        case write(Error)

        var errorDescription: String? {
            switch self {
            case .render: "Couldn't render the share card."
            case .encoding: "Couldn't encode the share card as a PNG."
            case .write(let error): "Couldn't save the share card: \(error.localizedDescription)"
            }
        }
    }

    /// Instagram Stories canvas — 9:16, 1080 wide. Same dimension every
    /// caller uses so previews and exports share one tuning.
    static let canvasSize = CGSize(width: 1080, height: 1920)

    /// Renders `model` as a 1080×1920 PNG and writes it to a temporary file.
    /// Returns the file URL for use with `UIActivityViewController`.
    /// `maskCompoundNames` swaps real peptide names for "Compound A/B/C"
    /// so a user can share without publishing their exact stack.
    static func renderPNG(for model: CycleCardModel, maskCompoundNames: Bool = false) throws -> URL {
        let image = try renderImage(for: model, maskCompoundNames: maskCompoundNames)
        guard let data = image.pngData() else { throw Failure.encoding }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: model))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.write(error)
        }
        return url
    }

    /// Renders `model` as an in-memory UIImage. Useful for unit tests and
    /// for any code path that needs the image without writing to disk.
    static func renderImage(for model: CycleCardModel, maskCompoundNames: Bool = false) throws -> UIImage {
        let view = CycleCardView(model: model, maskCompoundNames: maskCompoundNames)
            .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: canvasSize.width, height: canvasSize.height)
        // The view is authored at exact target pixel dimensions, so we render
        // at scale 1.0. Bumping the scale would explode memory and produce a
        // 3240×5760 image that no Stories surface expects.
        renderer.scale = 1.0
        renderer.isOpaque = true

        guard let image = renderer.uiImage else { throw Failure.render }
        return image
    }

    private static func filename(for model: CycleCardModel) -> String {
        let safeTitle = model.subjectTitle
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        let prefix = safeTitle.isEmpty ? "cycle" : safeTitle
        return "peptidex-\(prefix)-\(UUID().uuidString.prefix(6)).png"
    }
}
