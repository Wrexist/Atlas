import AVFoundation
import CoreGraphics
import Photos
import UIKit

enum WorkoutMediaError: LocalizedError, Equatable {
    case render, video, photoPermission
    var errorDescription: String? {
        switch self {
        case .render: "Could not create the image. Try again."
        case .video: "Could not create the video. Try again or share a Story image."
        case .photoPermission: "Allow Atlas to add photos in Settings, or use Share to save the file elsewhere."
        }
    }
}

/// AVFoundation encoding runs off the main actor, one frame at a time. No
/// frame array, network upload, audio capture, or third-party dependency.
actor WorkoutMediaExporter {
    static let frameRate: Int32 = 30
    static let frameCount = 180

    func video(image: CGImage, to url: URL, reduceMotion: Bool,
               progress: @escaping @Sendable (Double) async -> Void) async throws {
        let width = 1080, height = 1920
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
        guard writer.canAdd(input) else { throw WorkoutMediaError.video }
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true
        guard writer.startWriting() else { throw writer.error ?? WorkoutMediaError.video }
        writer.startSession(atSourceTime: .zero)
        do {
            for frame in 0..<Self.frameCount {
                try Task.checkCancellation()
                let deadline = Date().addingTimeInterval(15)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else {
                        throw writer.error ?? WorkoutMediaError.video
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                try autoreleasepool {
                    guard let pool = adaptor.pixelBufferPool else { throw WorkoutMediaError.video }
                    var output: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
                          let buffer = output else { throw WorkoutMediaError.video }
                    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw WorkoutMediaError.video }
                    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                        width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
                    else {
                        CVPixelBufferUnlockBaseAddress(buffer, [])
                        throw WorkoutMediaError.video
                    }
                    context.setFillColor(CGColor(gray: 0, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
                    // A short reveal with a gentle 1.5% push. All numbers are
                    // final logged values throughout; no invented counters.
                    let fraction = Double(frame) / Double(Self.frameCount - 1)
                    let scale = reduceMotion ? 1 : 1 + 0.015 * fraction
                    let w = CGFloat(width) * CGFloat(scale), h = CGFloat(height) * CGFloat(scale)
                    context.setAlpha(reduceMotion ? 1 : CGFloat(min(1, Double(frame + 1) / 12)))
                    context.interpolationQuality = .high
                    context.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2,
                        y: (CGFloat(height) - h) / 2, width: w, height: h))
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Self.frameRate))
                    else { throw writer.error ?? WorkoutMediaError.video }
                }
                if frame % 6 == 0 { await progress(Double(frame + 1) / Double(Self.frameCount)) }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: Int64(Self.frameCount), timescale: Self.frameRate))
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? WorkoutMediaError.video }
            await progress(1)
        } catch {
            writer.cancelWriting()
            WorkoutShareFiles.remove(url)
            throw error
        }
    }
}

enum WorkoutPhotoLibrary {
    static func save(url: URL, video: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        try Task.checkCancellation()
        guard status == .authorized || status == .limited else { throw WorkoutMediaError.photoPermission }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: video ? .video : .photo, fileURL: url, options: nil)
        }
    }
}
