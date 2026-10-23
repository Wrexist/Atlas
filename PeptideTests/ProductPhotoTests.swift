import XCTest
@testable import Peptide

final class ProductPhotoTests: XCTestCase {

    private var directory: URL!
    private var session: URLSession!
    private let photoURL = URL(string: "https://images.openfoodfacts.org/images/products/544/front_en.400.jpg")!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductPhotoTests-\(UUID().uuidString)", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        let png = Self.packshot.pngData()!
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, png)
        }
    }

    override func tearDown() {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Open Food Facts image choice

    func test_offRecordWithBothSizes_prefersTheFullFrontImage() throws {
        let product = try decodeProduct("""
        {"product_name": "Cola",
         "image_front_url": "https://images.openfoodfacts.org/images/products/1/front_en.400.jpg",
         "image_front_small_url": "https://images.openfoodfacts.org/images/products/1/front_en.200.jpg"}
        """)
        XCTAssertEqual(product.imageURL?.lastPathComponent, "front_en.400.jpg")
    }

    func test_offRecordWithOnlySmallImage_fallsBackToIt() throws {
        let product = try decodeProduct("""
        {"product_name": "Cola",
         "image_front_small_url": "https://images.openfoodfacts.org/images/products/1/front_en.200.jpg"}
        """)
        XCTAssertEqual(product.imageURL?.lastPathComponent, "front_en.200.jpg")
    }

    func test_offFrontImageOnForeignHost_fallsBackToTrustedSmallImage() throws {
        let product = try decodeProduct("""
        {"product_name": "Cola",
         "image_front_url": "https://tracker.example.com/front.jpg",
         "image_front_small_url": "https://images.openfoodfacts.org/images/products/1/front_en.200.jpg"}
        """)
        XCTAssertEqual(product.imageURL?.host, "images.openfoodfacts.org")
    }

    // MARK: - Cut-out sanity

    func test_maskSpanningMostOfThePack_keepsTheCutout() {
        let boxes = [TableLiftEngine.Box(label: 1, frame: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8))]
        XCTAssertTrue(ProductCutoutEngine.spansProduct(boxes))
    }

    func test_maskFindingOnlyALogo_fallsBackToTheWholePhoto() {
        let boxes = [TableLiftEngine.Box(label: 1, frame: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))]
        XCTAssertFalse(ProductCutoutEngine.spansProduct(boxes))
    }

    func test_separateInstancesAcrossThePack_countTogether() {
        let boxes = [
            TableLiftEngine.Box(label: 1, frame: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
            TableLiftEngine.Box(label: 2, frame: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2)),
        ]
        XCTAssertTrue(ProductCutoutEngine.spansProduct(boxes))
    }

    func test_emptyMask_isNotAProduct() {
        XCTAssertFalse(ProductCutoutEngine.spansProduct([]))
    }

    // MARK: - Store

    func test_cutout_isKeptOnDiskAndNotCutAgain() async {
        let first = ProductPhotoStore(directory: directory, session: session) { _ in Self.packshot }
        let photo = await first.photo(for: photoURL)
        XCTAssertEqual(photo?.isCutout, true)

        let counter = AttemptCounter()
        let relaunched = ProductPhotoStore(directory: directory, session: session) { _ in
            counter.bump()
            return nil
        }
        let again = await relaunched.photo(for: photoURL)
        XCTAssertEqual(again?.isCutout, true)
        XCTAssertEqual(counter.value, 0)
    }

    func test_noCleanEdge_keepsWholePhotoAndDoesNotRetry() async {
        let first = ProductPhotoStore(directory: directory, session: session) { _ in nil }
        let photo = await first.photo(for: photoURL)
        XCTAssertEqual(photo?.isCutout, false)

        let counter = AttemptCounter()
        let relaunched = ProductPhotoStore(directory: directory, session: session) { _ in
            counter.bump()
            return Self.packshot
        }
        let again = await relaunched.photo(for: photoURL)
        XCTAssertEqual(again?.isCutout, false)
        XCTAssertEqual(counter.value, 0)
    }

    func test_visionUnavailable_showsPhotoAndRetriesNextLaunch() async {
        let first = ProductPhotoStore(directory: directory, session: session) { _ in
            throw CocoaError(.featureUnsupported)
        }
        let photo = await first.photo(for: photoURL)
        XCTAssertEqual(photo?.isCutout, false)

        let relaunched = ProductPhotoStore(directory: directory, session: session) { _ in Self.packshot }
        let again = await relaunched.photo(for: photoURL)
        XCTAssertEqual(again?.isCutout, true)
    }

    func test_diskCache_keepsOnlyTheNewestFiles() async throws {
        let store = ProductPhotoStore(directory: directory, session: session, maxFiles: 2) { _ in Self.packshot }
        for index in 0..<4 {
            _ = await store.photo(for: URL(string: "https://images.openfoodfacts.org/\(index).jpg")!)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 2)
    }

    func test_missingImage_returnsNilSoArtworkStays() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        let store = ProductPhotoStore(directory: directory, session: session) { _ in Self.packshot }
        let photo = await store.photo(for: photoURL)
        XCTAssertNil(photo)
    }

    func test_loadedPhoto_isReadableSynchronouslyAfterwards() async {
        let store = ProductPhotoStore(directory: directory, session: session) { _ in Self.packshot }
        XCTAssertNil(store.cached(photoURL))
        _ = await store.photo(for: photoURL)
        XCTAssertNotNil(store.cached(photoURL))
    }

    // MARK: - Helpers

    private static let packshot: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }()

    private func decodeProduct(_ json: String) throws -> ScannedProduct {
        try JSONDecoder()
            .decode(OpenFoodFactsService.RawProduct.self, from: Data(json.utf8))
            .toScannedProduct(barcode: "1", fetchedAt: Date(timeIntervalSince1970: 0))
    }
}
