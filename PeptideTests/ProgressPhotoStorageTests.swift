import XCTest
import UIKit
@testable import Peptide

/// Covers the on-save downscale. Photos picked from the library arrive
/// at full camera resolution; before this existed they were JPEG-encoded
/// and written as-is, so a 48 MP shot cost tens of megabytes on disk and
/// a full-resolution decode on every render.
final class ProgressPhotoStorageTests: XCTestCase {

    /// Scale 1 so the fixture's points and pixels are the same number —
    /// the default renderer inherits the screen's scale, which would
    /// make every size assertion here device-dependent.
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func test_downscaled_measuresPixelsNotPoints() {
        // A 1200×900 image at 3× is 3600×2700 pixels — over the ceiling,
        // even though its `size` reads as comfortably under it.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900), format: format)
        let retina = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }

        let result = ProgressPhotoStorage.downscaled(retina)
        XCTAssertEqual(max(result.size.width, result.size.height) * result.scale, 2000, accuracy: 1)
    }

    func test_downscaled_oversizedLandscape_capsTheLongestEdge() {
        let result = ProgressPhotoStorage.downscaled(image(width: 4032, height: 3024))
        XCTAssertEqual(result.size.width, 2000, accuracy: 1)
        XCTAssertEqual(result.size.height, 1500, accuracy: 1)
    }

    func test_downscaled_oversizedPortrait_capsTheLongestEdge() {
        let result = ProgressPhotoStorage.downscaled(image(width: 3024, height: 4032))
        XCTAssertEqual(result.size.height, 2000, accuracy: 1)
        XCTAssertEqual(result.size.width, 1500, accuracy: 1)
    }

    func test_downscaled_preservesAspectRatio() {
        let source = image(width: 4000, height: 2250)
        let result = ProgressPhotoStorage.downscaled(source)
        XCTAssertEqual(
            result.size.width / result.size.height,
            source.size.width / source.size.height,
            accuracy: 0.01
        )
    }

    func test_downscaled_alreadySmallEnough_returnsTheOriginal() {
        // Re-rendering a photo that's already under the ceiling would
        // cost quality for nothing.
        let source = image(width: 1200, height: 900)
        let result = ProgressPhotoStorage.downscaled(source)
        XCTAssertEqual(result.size, source.size)
    }

    func test_downscaled_exactlyAtTheCeiling_isUntouched() {
        let source = image(width: 2000, height: 1000)
        let result = ProgressPhotoStorage.downscaled(source)
        XCTAssertEqual(result.size, source.size)
    }

    // MARK: - Round trip

    func test_save_thenDelete_leavesNoFileBehind() throws {
        let filename = try ProgressPhotoStorage.save(image(width: 3000, height: 3000))
        addTeardownBlock { ProgressPhotoStorage.delete(filename: filename) }

        let url = try ProgressPhotoStorage.url(for: filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        ProgressPhotoStorage.delete(filename: filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_save_writesTheDownscaledImage() throws {
        let filename = try ProgressPhotoStorage.save(image(width: 4000, height: 3000))
        addTeardownBlock { ProgressPhotoStorage.delete(filename: filename) }

        let url = try ProgressPhotoStorage.url(for: filename)
        let written = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        XCTAssertEqual(max(written.size.width, written.size.height), 2000, accuracy: 1)
    }
}
