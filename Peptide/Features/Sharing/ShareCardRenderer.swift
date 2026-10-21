import SwiftUI
import UIKit

/// Renders a `CycleCardView` to a PNG file in the temporary directory, at
/// the exact pixel size of the requested `ShareFormat`. The watermark is part of the same view tree, so a single
/// `ImageRenderer` pass produces one composited image — there is no
/// detachable layer for the brand mark.
@MainActor
enum ShareCardRenderer {
    enum Failure: LocalizedError {
        case render
        case encoding
        case write

        var errorDescription: String? {
            switch self {
            case .render: "Couldn't render the share card."
            case .encoding: "Couldn't encode the share card as a PNG."
            case .write: "Couldn't save the share card. Check your free storage and try again."
            }
        }
    }

    /// Renders `model` as a PNG in `format` and writes it to a temporary
    /// file. Returns the file URL for use with `UIActivityViewController`.
    /// `maskCompoundNames` swaps real peptide names for "Compound A/B/C"
    /// so a user can share without publishing their exact stack.
    static func renderPNG(
        for model: CycleCardModel,
        format: ShareFormat = .story,
        maskCompoundNames: Bool = false
    ) throws -> URL {
        let image = try renderImage(for: model, format: format, maskCompoundNames: maskCompoundNames)
        guard let data = image.pngData() else { throw Failure.encoding }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: model))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.export.error("Share card write failed: \(error.localizedDescription, privacy: .public)")
            throw Failure.write
        }
        return url
    }

    /// Renders `model` as an in-memory UIImage. Useful for unit tests and
    /// for any code path that needs the image without writing to disk.
    static func renderImage(
        for model: CycleCardModel,
        format: ShareFormat = .story,
        maskCompoundNames: Bool = false
    ) throws -> UIImage {
        let canvasSize = format.pixelSize
        let view = CycleCardView(model: model, maskCompoundNames: maskCompoundNames, format: format)
            .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: canvasSize.width, height: canvasSize.height)
        // The view is authored at exact target pixel dimensions, so we render
        // at scale 1.0. Bumping the scale would explode memory and produce a
        // 3× image that no destination expects.
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
        // "atlas-" prefix — was "peptidex-" which leaked the
        // pre-rebrand product name into AirDrop / share sheet
        // filenames (audit Sharing P2.13).
        return "atlas-\(prefix)-\(UUID().uuidString.prefix(6)).png"
    }
}
