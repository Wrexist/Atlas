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

    // MARK: - Backup includes customization fields

    func test_jsonBackup_roundTripsAvatarBioAndPrimaryGoal() throws {
        // The export pipeline relies on UserProfile.Codable to capture the
        // whole profile. This guards against a future regression where a new
        // field is added to the model but missed in the backup.
        var profile = dataStore.profile
        profile.avatarImageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        profile.bio = "Optimizing recovery."
        profile.goals = ["Better Sleep", "Recovery"]
        profile.primaryGoal = "Better Sleep"

        let data = try XCTUnwrap(
            ExportService.shared.exportFullBackup(
                protocols: dataStore.protocols,
                entries: dataStore.entries,
                profile: profile
            )
        )

        // Decode back through the same pipeline a restore would use.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)

        XCTAssertEqual(backup.profile.avatarImageData, profile.avatarImageData)
        XCTAssertEqual(backup.profile.bio, "Optimizing recovery.")
        XCTAssertEqual(backup.profile.primaryGoal, "Better Sleep")
    }
}
