import SwiftUI
import UIKit

/// Renders a `CycleCardView` to a PNG file in the export directory, at
/// the exact pixel size of the requested `ShareFormat`. The watermark is
/// part of the same view tree, so a single `ImageRenderer` pass produces
/// one composited image — there is no detachable layer for the brand mark.
@MainActor
enum ShareCardRenderer {
    enum Failure: LocalizedError {
        case render
        case encoding
        case write

        var errorDescription: String? {
            switch self {
            case .render: String(localized: "Couldn't render the share card.")
            case .encoding: String(localized: "Couldn't encode the share card as a PNG.")
            case .write: String(localized: "Couldn't save the share card. Check your free storage and try again.")
            }
        }
    }

    /// Renders `model` as a PNG in `format` and writes it to the export
    /// directory. Returns the file URL for use with `UIActivityViewController`.
    /// `maskCompoundNames` swaps real peptide names for "Compound A/B/C"
    /// so a user can share without publishing their exact stack.
    static func renderPNG(
        for model: CycleCardModel,
        format: ShareFormat = .story,
        maskCompoundNames: Bool = false
    ) throws -> URL {
        let image = try renderImage(for: model, format: format, maskCompoundNames: maskCompoundNames)
        guard let data = image.pngData() else { throw Failure.encoding }

        // Shares go in the export folder so "Delete All Data" and the next
        // export or share sweep them; the card can carry compound names
        // and health figures.
        ExportService.shared.clearExports()
        let directory = ExportService.exportDirectory
        let url = directory.appendingPathComponent(filename(for: model, maskCompoundNames: maskCompoundNames))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            AppLog.export.error("Share card write failed: \(error.localizedDescription, privacy: .public)")
            throw Failure.write
        }
        return url
    }

    /// Renders `model` as an in-memory UIImage. Useful for unit tests and
    /// for any code path that needs the image without writing to disk.
    /// `scale` below 1 renders a smaller bitmap for an on-screen preview.
    static func renderImage(
        for model: CycleCardModel,
        format: ShareFormat = .story,
        maskCompoundNames: Bool = false,
        scale: CGFloat = 1
    ) throws -> UIImage {
        let canvasSize = format.pixelSize
        let view = CycleCardView(model: model, maskCompoundNames: maskCompoundNames, format: format)
            .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: canvasSize.width, height: canvasSize.height)
        // The view is authored at exact target pixel dimensions, so exports
        // render at scale 1. Bumping it would explode memory and produce a
        // 3× image that no destination expects.
        renderer.scale = scale
        renderer.isOpaque = true

        guard let image = renderer.uiImage else { throw Failure.render }
        return image
    }

    /// A masked card falls back to "atlas-cycle-…" so the file name shown
    /// in AirDrop and Messages doesn't leak the protocol name either.
    private static func filename(for model: CycleCardModel, maskCompoundNames: Bool) -> String {
        let title = maskCompoundNames ? "" : model.subjectTitle
        let safeTitle = title
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
