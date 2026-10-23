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

    // MARK: - CSV

    func test_csvDate_lateEveningInNegativeOffset_usesLocalCalendarDay() throws {
        let original = NSTimeZone.default
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        NSTimeZone.default = losAngeles
        defer { NSTimeZone.default = original }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let lateEvening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 23, minute: 30)))
        let entry = ProtocolEntry(
            id: UUID(), protocolId: UUID(), peptide: MockPeptides.bpc157,
            date: lateEvening, dose: "250 mcg", notes: "", completed: true
        )

        let csv = ExportService.shared.exportProtocolsCSV(protocols: [], entries: [entry])

        let row = try XCTUnwrap(csv.split(separator: "\n").dropFirst().first)
        XCTAssertTrue(row.hasPrefix("2026-03-14,"), "Got \(row)")
    }

    func test_monthlyBuckets_roundsCompliance() {
        let day = Date()
        let entries = [true, true, false].map { completed in
            ProtocolEntry(
                id: UUID(), protocolId: UUID(), peptide: MockPeptides.bpc157,
                date: day, dose: "250 mcg", notes: "", completed: completed
            )
        }

        let buckets = ExportService.monthlyBuckets(for: entries)

        XCTAssertEqual(buckets.map(\.compliancePct), [67])
    }

    func test_protocolCSV_usesActualTimeWhenPresent() throws {
        let scheduled = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 8)))
        let taken = scheduled.addingTimeInterval(2 * 60 * 60 + 15 * 60)
        var entry = ProtocolEntry(
            id: UUID(), protocolId: UUID(), peptide: MockPeptides.bpc157,
            date: scheduled, dose: "250 mcg", notes: "", completed: true
        )
        entry.actualTime = taken

        let csv = ExportService.shared.exportProtocolsCSV(protocols: [], entries: [entry])

        let row = try XCTUnwrap(csv.split(separator: "\n").dropFirst().first)
        XCTAssertTrue(row.contains(taken.formatted(.dateTime.hour().minute())), "Got \(row)")
        XCTAssertFalse(row.contains(scheduled.formatted(.dateTime.hour().minute())), "Got \(row)")
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

    // MARK: - Temp export cleanup

    func test_newExport_removesThePreviousExportFile() throws {
        let first = try XCTUnwrap(ExportService.shared.writeCSV("a", filename: "first.csv"))
        let second = try XCTUnwrap(ExportService.shared.writeJSON(Data("{}".utf8), filename: "second.json"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func test_writeCSV_roundTripsContentInsideExportDirectory() throws {
        let url = try XCTUnwrap(ExportService.shared.writeCSV("name,dose\nBPC,250", filename: "../escape.csv"))

        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, ExportService.exportDirectory.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "name,dose\nBPC,250")
    }

    func test_clearExports_removesEveryExportFile() throws {
        let url = try XCTUnwrap(ExportService.shared.writeCSV("a", filename: "clear.csv"))

        ExportService.shared.clearExports()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
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
