import UIKit
import XCTest
@testable import Peptide

final class AvatarImageNormalizerTests: XCTestCase {

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(of data: Data?) -> (width: Int, height: Int)? {
        guard let data, let cgImage = UIImage(data: data)?.cgImage else { return nil }
        return (cgImage.width, cgImage.height)
    }

    func test_normalizeImage_4000x3000_returns1024PixelSquare() {
        let size = pixelSize(of: AvatarImageNormalizer.normalize(image: solidImage(width: 4000, height: 3000)))
        XCTAssertEqual(size?.width, 1024)
        XCTAssertEqual(size?.height, 1024)
    }

    func test_normalizeRawData_4000x3000_returnsSquareNoLargerThan1024Pixels() {
        let raw = solidImage(width: 4000, height: 3000).jpegData(compressionQuality: 0.9)
        guard let raw, let size = pixelSize(of: AvatarImageNormalizer.normalize(rawImageData: raw)) else {
            XCTFail("A JPEG photo must normalize")
            return
        }
        XCTAssertEqual(size.width, size.height)
        XCTAssertLessThanOrEqual(size.width, 1024)
        XCTAssertGreaterThanOrEqual(size.width, 1020)
    }

    func test_normalizeImage_smallerThanTarget_isNotUpscaled() {
        let size = pixelSize(of: AvatarImageNormalizer.normalize(image: solidImage(width: 300, height: 400)))
        XCTAssertEqual(size?.width, 300)
        XCTAssertEqual(size?.height, 300)
    }

    func test_normalizeRawData_notAnImage_returnsNil() {
        XCTAssertNil(AvatarImageNormalizer.normalize(rawImageData: Data("not an image".utf8)))
    }
}
