import XCTest
import AVFoundation
import UIKit
@testable import Peptide

@MainActor
final class WorkoutSocialShareTests: XCTestCase {
    private func summary() async -> WorkoutRecapEngine.Summary {
        await ExerciseLibrary.shared.load()
        let session = WorkoutRecapFixture.push()
        let catalog = Dictionary(uniqueKeysWithValues: session.exercises.compactMap { entry in
            ExerciseLibrary.shared.lookup(id: entry.exerciseID).map { (entry.exerciseID, $0) }
        })
        return WorkoutRecapEngine.derive(session, catalog: catalog)
    }

    func test_allStylesAndFormatsRenderExactPixelDimensions() async throws {
        let summary = await summary()
        for style in WorkoutShareStyle.allCases {
            for format in WorkoutShareFormat.allCases {
                var options = WorkoutShareOptions()
                options.style = style
                options.format = format
                options.includeDate = true
                let image = try XCTUnwrap(WorkoutSocialRenderer.image(summary: summary, unit: .imperial, options: options).cgImage)
                XCTAssertEqual(image.width, Int(format.pixelSize.width))
                XCTAssertEqual(image.height, Int(format.pixelSize.height))
                let attachment = XCTAttachment(image: UIImage(cgImage: image))
                attachment.name = "social-\(style.rawValue)-\(format.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func test_reelEncodesSixSecondPortraitVideoWithoutAudio() async throws {
        var options = WorkoutShareOptions()
        options.format = .reel
        let recap = await summary()
        let image = try XCTUnwrap(WorkoutSocialRenderer.image(summary: recap, unit: .metric, options: options).cgImage)
        let url = WorkoutShareFiles.makeURL(video: true)
        defer { WorkoutShareFiles.remove(url) }
        try await WorkoutMediaExporter().video(image: image, to: url, reduceMotion: true) { _ in }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 6, accuracy: 0.05)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
        let generator = AVAssetImageGenerator(asset: asset)
        let frame = try await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600))
        let attachment = XCTAttachment(image: UIImage(cgImage: frame.image))
        attachment.name = "social-reel-decoded-frame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_cancelledVideoLeavesNoPartialFile() async throws {
        let recap = await summary()
        let image = try XCTUnwrap(WorkoutSocialRenderer.image(summary: recap, unit: .metric,
                                                              options: WorkoutShareOptions()).cgImage)
        let url = WorkoutShareFiles.makeURL(video: true)
        defer { WorkoutShareFiles.remove(url) }
        let task = Task {
            try await WorkoutMediaExporter().video(image: image, to: url, reduceMotion: false) { _ in }
        }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_exportFileNamesAreAnonymousAndUnique() {
        let first = WorkoutShareFiles.makeURL(video: false)
        let second = WorkoutShareFiles.makeURL(video: false)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.pathExtension, "png")
        XCTAssertEqual(WorkoutShareFiles.makeURL(video: true).pathExtension, "mp4")
        XCTAssertTrue(first.lastPathComponent.hasPrefix("atlas-workout-"))
    }

    func test_cachedExportIsInvalidatedByPrivacyUnitsAndSavedEdits() async throws {
        let recap = await summary()
        let controller = WorkoutShareController()
        var options = WorkoutShareOptions()
        let first = try await export(controller, recap: recap, unit: .metric, options: options)
        let reused = try await export(controller, recap: recap, unit: .metric, options: options)
        XCTAssertEqual(first, reused)
        options.includeName = false
        let hiddenName = try await export(controller, recap: recap, unit: .metric, options: options)
        XCTAssertNotEqual(first, hiddenName)
        let imperial = try await export(controller, recap: recap, unit: .imperial, options: options)
        XCTAssertNotEqual(hiddenName, imperial)
        var session = recap.session
        session.name = "Edited saved workout"
        let edited = WorkoutRecapEngine.derive(session, catalog: [:])
        let afterEdit = try await export(controller, recap: edited, unit: .imperial, options: options)
        XCTAssertEqual(edited.session.id, recap.session.id)
        XCTAssertNotEqual(imperial, afterEdit)
        XCTAssertTrue(FileManager.default.fileExists(atPath: afterEdit.path))
    }

    private func export(_ controller: WorkoutShareController, recap: WorkoutRecapEngine.Summary,
                        unit: MeasurementUnit, options: WorkoutShareOptions) async throws -> URL {
        controller.perform(.share, summary: recap, unit: unit, options: options, reduceMotion: true)
        for _ in 0..<300 {
            if !controller.busy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(controller.busy)
        XCTAssertNil(controller.error)
        let url = try XCTUnwrap(controller.exportItem?.url)
        controller.exportItem = nil
        return url
    }
}
