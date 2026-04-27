import XCTest
@testable import Peptide

@MainActor
final class ExportServiceTests: XCTestCase {

    private var dataStore: DataStore!

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        dataStore = DataStore(seedSampleData: true)
    }

    override func tearDown() {
        SwiftDataRepository.shared.deleteAll()
        dataStore = nil
        super.tearDown()
    }

    // MARK: - PDF

    func test_pdfExport_producesNonEmptyData() throws {
        let data = try ExportService.shared.exportPDF(
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            profile: dataStore.profile
        )
        XCTAssertFalse(data.isEmpty)
    }

    func test_pdfExport_producesPDFHeader() throws {
        let data = try ExportService.shared.exportPDF(
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            profile: dataStore.profile
        )
        // PDF files begin with the %PDF- magic bytes
        let magic = data.prefix(5)
        XCTAssertEqual(String(bytes: magic, encoding: .ascii), "%PDF-")
    }

    func test_pdfExport_withEmptyData_stillProducesValidPDF() throws {
        let data = try ExportService.shared.exportPDF(
            protocols: [],
            entries: [],
            profile: .fresh
        )
        let magic = data.prefix(5)
        XCTAssertEqual(String(bytes: magic, encoding: .ascii), "%PDF-")
    }

    func test_writePDF_returnsURL_andFileExists() throws {
        let data = try ExportService.shared.exportPDF(
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            profile: dataStore.profile
        )
        let url = ExportService.shared.writePDF(data, filename: "test-report.pdf")
        XCTAssertNotNil(url)
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - Error type

    func test_exportError_localizedDescription_isHumanReadable() {
        let error = ExportError.pdfGenerationFailed
        XCTAssertEqual(error.errorDescription, "PDF report could not be generated.")
    }
}
