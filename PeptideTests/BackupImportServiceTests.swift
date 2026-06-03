import XCTest
@testable import Peptide

@MainActor
final class BackupImportServiceTests: XCTestCase {

    // MARK: - Validate

    func test_validate_rejectsOversizedBlob() {
        // 51 MB > 50 MB cap — should reject without attempting decode.
        let huge = Data(repeating: 0x7B /* `{` */, count: 51 * 1024 * 1024)
        XCTAssertThrowsError(try BackupImportService.validate(huge)) { error in
            guard case BackupImportService.ImportError.fileTooLarge = error else {
                return XCTFail("Expected .fileTooLarge, got \(error)")
            }
        }
    }

    func test_validate_rejectsMalformedJSON() {
        let bytes = Data("definitely { not valid json".utf8)
        XCTAssertThrowsError(try BackupImportService.validate(bytes)) { error in
            guard case BackupImportService.ImportError.invalidJSON = error else {
                return XCTFail("Expected .invalidJSON, got \(error)")
            }
        }
    }

    func test_validate_rejectsUnsupportedMajorVersion() throws {
        let backup = AppBackup(
            exportDate: Date(),
            version: "99.0",
            protocols: [],
            entries: [],
            profile: .fresh
        )
        let data = try encode(backup)
        XCTAssertThrowsError(try BackupImportService.validate(data)) { error in
            guard case BackupImportService.ImportError.unsupportedVersion = error else {
                return XCTFail("Expected .unsupportedVersion, got \(error)")
            }
        }
    }

    func test_validate_rejectsFutureExportDate() throws {
        let backup = AppBackup(
            exportDate: Date().addingTimeInterval(7 * 24 * 60 * 60), // a week ahead
            version: "1.0",
            protocols: [],
            entries: [],
            profile: .fresh
        )
        let data = try encode(backup)
        XCTAssertThrowsError(try BackupImportService.validate(data)) { error in
            guard case BackupImportService.ImportError.bounds = error else {
                return XCTFail("Expected .bounds, got \(error)")
            }
        }
    }

    func test_validate_succeedsOnValidBackup() throws {
        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: [],
            entries: [],
            profile: makeProfile(named: "Alex")
        )
        let data = try encode(backup)
        let (parsed, preview) = try BackupImportService.validate(data)
        XCTAssertEqual(parsed.version, "1.0")
        XCTAssertEqual(preview.profileName, "Alex")
        XCTAssertEqual(preview.protocolsCount, 0)
    }

    // MARK: - Apply

    func test_dryRun_doesNotMutate() throws {
        let dataStore = makeDataStore()
        let initialCount = dataStore.protocols.count

        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: [makeProtocol(named: "Imported A"), makeProtocol(named: "Imported B")],
            entries: [],
            profile: makeProfile(named: "From Backup")
        )

        let preview = try BackupImportService.apply(
            backup, strategy: .dryRun, into: dataStore
        )
        XCTAssertEqual(preview.protocolsCount, 2,
                       "DryRun preview should reflect backup contents")
        XCTAssertEqual(dataStore.protocols.count, initialCount,
                       "DryRun must not write anything to the live store")
    }

    func test_replace_wipesAndRestores() throws {
        let dataStore = makeDataStore()
        let preExisting = makeProtocol(named: "Existing")
        dataStore.addProtocol(preExisting)
        XCTAssertEqual(dataStore.protocols.count, 1)

        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: [makeProtocol(named: "Backup A"), makeProtocol(named: "Backup B")],
            entries: [],
            profile: makeProfile(named: "Backup user")
        )
        _ = try BackupImportService.apply(backup, strategy: .replace, into: dataStore)

        XCTAssertEqual(dataStore.protocols.count, 2)
        XCTAssertFalse(
            dataStore.protocols.contains { $0.id == preExisting.id },
            "Replace must drop the pre-existing protocol"
        )
        XCTAssertEqual(dataStore.profile.name, "Backup user")
    }

    func test_replace_forcesWorkoutMigrationMarker() throws {
        let dataStore = makeDataStore()
        // Simulate a pre-Plan-C backup: marker false, history non-empty.
        var backupProfile = makeProfile(named: "Pre-PlanC")
        backupProfile.workoutLegacyMigrationCompleted = false
        backupProfile.workoutHistory = [
            WorkoutEntry(date: Date(), name: "Legacy", sets: 1, reps: 1, durationMinutes: 30)
        ]
        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: [],
            entries: [],
            profile: backupProfile
        )
        _ = try BackupImportService.apply(backup, strategy: .replace, into: dataStore)

        XCTAssertTrue(dataStore.profile.workoutLegacyMigrationCompleted,
                      "Replace must force the migration marker so the next launch doesn't re-migrate")
        XCTAssertTrue(dataStore.profile.workoutHistory.isEmpty,
                      "Legacy array must be cleared on the restored profile")
    }

    func test_merge_keepsExistingOnConflict() throws {
        let dataStore = makeDataStore()
        let shared = makeProtocol(named: "Original")
        dataStore.addProtocol(shared)

        // Build a "backup" that contains the same ID with a different
        // name — merge should keep the existing one. `PeptideProtocol`
        // is immutable (`let name`), so reconstruct rather than mutate.
        let conflictingProto = PeptideProtocol(
            id: shared.id,
            name: "Backup version",
            peptides: shared.peptides,
            schedule: shared.schedule,
            peptideSchedules: shared.peptideSchedules,
            cycleLengthWeeks: shared.cycleLengthWeeks,
            washoutWeeks: shared.washoutWeeks,
            startDate: shared.startDate,
            status: shared.status,
            notes: shared.notes,
            authorName: shared.authorName,
            authorHandle: shared.authorHandle,
            forkedFromStackId: shared.forkedFromStackId,
            createdAt: shared.createdAt
        )
        let unique = makeProtocol(named: "Backup-only")

        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: [conflictingProto, unique],
            entries: [],
            profile: dataStore.profile
        )
        _ = try BackupImportService.apply(backup, strategy: .merge, into: dataStore)

        XCTAssertEqual(dataStore.protocols.count, 2,
                       "Merge should add the unique backup proto without removing the existing one")
        XCTAssertEqual(
            dataStore.protocols.first { $0.id == shared.id }?.name,
            "Original",
            "Merge keeps the user's current name on ID conflict"
        )
    }

    // MARK: - Helpers

    private func makeDataStore() -> DataStore {
        SwiftDataRepository.shared.configureForTesting()
        return DataStore(seedSampleData: false)
    }

    private func encode(_ backup: AppBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    private func makeProtocol(named name: String) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: name,
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1,2,3,4,5,6,7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: .active,
            notes: ""
        )
    }

    private func makeProfile(named name: String) -> UserProfile {
        var p = UserProfile.fresh
        p.name = name
        return p
    }
}
