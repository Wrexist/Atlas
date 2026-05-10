import SwiftUI
import UIKit

/// Renders a `CycleCardView` to a 1080×1350 PNG file in the temporary
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

    static let canvasSize = CGSize(width: 1080, height: 1350)

    /// Renders `proto` as a 1080×1350 PNG and writes it to a temporary file.
    /// Returns the file URL for use with `UIActivityViewController`.
    static func renderPNG(for proto: PeptideProtocol) throws -> URL {
        let image = try renderImage(for: proto)
        guard let data = image.pngData() else { throw Failure.encoding }

        let safeName = proto.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        let prefix = safeName.isEmpty ? "cycle" : safeName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("peptidex-\(prefix)-\(UUID().uuidString.prefix(6)).png")

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.write(error)
        }
        return url
    }

    /// Renders `proto` as an in-memory UIImage. Useful for unit tests and
    /// for any code path that needs the image without writing to disk.
    static func renderImage(for proto: PeptideProtocol) throws -> UIImage {
        let view = CycleCardView(proto: proto)
            .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: canvasSize.width, height: canvasSize.height)
        // The view is authored at exact target pixel dimensions, so we render
        // at scale 1.0. Bumping the scale here would explode memory and
        // produce a 3240×4050 image that no platform expects.
        renderer.scale = 1.0
        renderer.isOpaque = true

        guard let image = renderer.uiImage else { throw Failure.render }
        return image
    }
}
