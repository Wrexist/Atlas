import XCTest
@testable import Peptide

final class BarcodeProductCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarcodeCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
    }

    private func makeCache(ttl: TimeInterval = 60) -> BarcodeProductCache {
        BarcodeProductCache(directory: tempDir, ttl: ttl)
    }

    private func sample(barcode: String = "5449000000996") -> ScannedProduct {
        ScannedProduct(
            barcode: barcode,
            name: "Coca-Cola",
            brand: "Coca-Cola",
            imageURL: URL(string: "https://example.com/coke.jpg"),
            servingSizeText: "330 ml",
            servingGrams: 330,
            packageGrams: 330,
            per100g: .init(calories: 42, proteinG: 0, carbsG: 10.6, fatG: 0, fiberG: 0, sugarsG: 10.6),
            nutriScore: "e",
            novaGroup: 4,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Round-trip

    func test_read_returnsNil_forUnknownBarcode() async {
        let cache = makeCache()
        let result = await cache.read(barcode: "0000000000000")
        XCTAssertNil(result)
    }

    func test_write_thenRead_returnsSameProduct() async {
        let cache = makeCache()
        let product = sample()
        await cache.write(product)
        let read = await cache.read(barcode: product.barcode)
        XCTAssertEqual(read, product)
    }

    func test_write_overwritesExistingEntry() async {
        let cache = makeCache()
        let original = sample()
        await cache.write(original)

        let updated = ScannedProduct(
            barcode: original.barcode,
            name: "Coca-Cola Zero",      // changed
            brand: original.brand,
            imageURL: original.imageURL,
            servingSizeText: original.servingSizeText,
            servingGrams: original.servingGrams,
            packageGrams: original.packageGrams,
            per100g: original.per100g,
            nutriScore: original.nutriScore,
            novaGroup: original.novaGroup,
            fetchedAt: original.fetchedAt
        )
        await cache.write(updated)
        let read = await cache.read(barcode: updated.barcode)
        XCTAssertEqual(read?.name, "Coca-Cola Zero")
    }

    // MARK: - TTL

    func test_read_returnsNil_whenEntryIsExpired() async {
        // Negative TTL means "always expired" — guarantees the
        // staleness branch fires without sleeping in the test.
        let cache = makeCache(ttl: -1)
        await cache.write(sample())
        let read = await cache.read(barcode: sample().barcode)
        XCTAssertNil(read)
    }

    func test_read_returnsEntry_withinTTL() async {
        let cache = makeCache(ttl: 60 * 60)
        await cache.write(sample())
        let read = await cache.read(barcode: sample().barcode)
        XCTAssertNotNil(read)
    }

    // MARK: - Clear

    func test_clear_removesAllEntries() async {
        let cache = makeCache()
        await cache.write(sample(barcode: "1111111111111"))
        await cache.write(sample(barcode: "2222222222222"))
        await cache.clear()
        let a = await cache.read(barcode: "1111111111111")
        let b = await cache.read(barcode: "2222222222222")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }

    func test_clear_leavesDirectoryWritable() async {
        let cache = makeCache()
        await cache.write(sample())
        await cache.clear()
        await cache.write(sample())              // must not throw
        let read = await cache.read(barcode: sample().barcode)
        XCTAssertNotNil(read)
    }

    // MARK: - Corruption tolerance

    func test_read_returnsNil_whenFileIsCorrupted() async {
        let cache = makeCache()
        let url = tempDir.appendingPathComponent("9999999999999.json")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? Data("not valid json".utf8).write(to: url)
        let read = await cache.read(barcode: "9999999999999")
        XCTAssertNil(read)
    }

    // MARK: - recent()

    func test_recent_returnsEmpty_whenCacheIsEmpty() async {
        let cache = makeCache()
        let recent = await cache.recent(limit: 5)
        XCTAssertTrue(recent.isEmpty)
    }

    func test_recent_returnsMostRecentlyWrittenFirst() async throws {
        let cache = makeCache()
        await cache.write(sample(barcode: "1111111111111"))
        // Force a measurable mtime gap so the ordering is deterministic
        // on file systems that don't store sub-second resolution.
        try await Task.sleep(for: .milliseconds(1100))
        await cache.write(sample(barcode: "2222222222222"))
        try await Task.sleep(for: .milliseconds(1100))
        await cache.write(sample(barcode: "3333333333333"))

        let recent = await cache.recent(limit: 5)
        XCTAssertEqual(recent.map(\.barcode), ["3333333333333", "2222222222222", "1111111111111"])
    }

    func test_recent_capsAtLimit() async {
        let cache = makeCache()
        for i in 0..<6 {
            await cache.write(sample(barcode: "100000000000\(i)"))
        }
        let recent = await cache.recent(limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func test_recent_skipsExpiredEntries() async {
        let cache = BarcodeProductCache(directory: tempDir, ttl: -1)
        await cache.write(sample())
        let recent = await cache.recent(limit: 5)
        XCTAssertTrue(recent.isEmpty)
    }

    // MARK: - LRU eviction

    func test_write_evictsOldestWhenAboveCap() async throws {
        let cache = BarcodeProductCache(directory: tempDir, ttl: 60 * 60, maxEntries: 3)
        await cache.write(sample(barcode: "1111111111111"))
        try await Task.sleep(for: .milliseconds(1100))
        await cache.write(sample(barcode: "2222222222222"))
        try await Task.sleep(for: .milliseconds(1100))
        await cache.write(sample(barcode: "3333333333333"))
        try await Task.sleep(for: .milliseconds(1100))
        await cache.write(sample(barcode: "4444444444444"))      // pushes #1 out

        let one   = await cache.read(barcode: "1111111111111")
        let four  = await cache.read(barcode: "4444444444444")
        XCTAssertNil(one,  "Oldest entry should be evicted once over the cap")
        XCTAssertNotNil(four)
    }
}
