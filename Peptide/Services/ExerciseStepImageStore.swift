import AVFoundation
import CoreGraphics

/// The step pictures, cut from the exercise's downloaded clip at the
/// guide's moments and cropped to the figure. Cutting them on the device
/// keeps the pictures and the video from ever disagreeing, and needs no
/// second download. Kept in memory for the session.
@MainActor
final class ExerciseStepImageStore {
    static let shared = ExerciseStepImageStore()

    private var cache: [String: [CGImage]] = [:]

    /// One picture per step, in order; nil when a frame can't be read.
    func images(from clip: URL, guide: ExerciseStepGuide.Guide) async -> [CGImage]? {
        let key = "\(clip.lastPathComponent)|\(guide.steps.map(\.time))"
        if let cached = cache[key] { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var images: [CGImage] = []
        for step in guide.steps {
            let time = CMTime(seconds: step.time, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time),
                  let cropped = Self.crop(frame.image, to: guide.crop) else { return nil }
            images.append(cropped)
        }
        cache[key] = images
        return images
    }

    /// `unit` is in unit coordinates with the origin top left, as CGImage
    /// pixel rows run.
    nonisolated static func crop(_ image: CGImage, to unit: CGRect) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(
            x: unit.minX * full.width, y: unit.minY * full.height,
            width: unit.width * full.width, height: unit.height * full.height
        ).integral.intersection(full)
        guard !rect.isEmpty else { return nil }
        return image.cropping(to: rect)
    }
}
