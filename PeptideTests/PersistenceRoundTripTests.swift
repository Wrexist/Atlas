import XCTest
@testable import Peptide

@MainActor
final class PersistenceRoundTripTests: XCTestCase {

    private let persistence = PersistenceService.shared

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        persistence.clearAll()
    }

    override func tearDown() {
        SwiftDataRepository.shared.deleteAll()
        persistence.clearAll()
        super.tearDown()
    }

    // MARK: - Encoder/Decoder (matches PersistenceService config)

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Group 1: PersistenceService Low-Level Round-Trip

    func test_saveAndLoadProtocols_roundTrip() {
        let original = MockProtocols.all
        persistence.saveProtocols(original)

        let loaded = persistence.loadProtocols()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.count, original.count)
        for (orig, load) in zip(original, loaded!) {
            XCTAssertEqual(orig.id, load.id)
            XCTAssertEqual(orig.name, load.name)
            XCTAssertEqual(orig.status, load.status)
            XCTAssertEqual(orig.peptides.count, load.peptides.count)
            XCTAssertEqual(orig.schedule.daysOfWeek, load.schedule.daysOfWeek)
            XCTAssertEqual(orig.schedule.timesPerDay, load.schedule.timesPerDay)
            XCTAssertEqual(orig.schedule.preferredTimes, load.schedule.preferredTimes)
            XCTAssertEqual(orig.cycleLengthWeeks, load.cycleLengthWeeks)
            XCTAssertEqual(orig.notes, load.notes)
        }
    }

    func test_saveAndLoadEntries_roundTrip() {
        let store = DataStore(seedSampleData: true)
        let original = store.entries

        XCTAssertFalse(original.isEmpty, "Seeded store should have entries")

        // Entries were already saved to SwiftData by DataStore.init(seedSampleData: true).
        // Reload from SwiftData.
        let loaded = SwiftDataRepository.shared.loadEntries()
        XCTAssertFalse(loaded.isEmpty)
        XCTAssertEqual(loaded.count, original.count)

        // Spot-check a known entry
        let origFirst = original.first!
        let reloaded = loaded.first(where: { $0.id == origFirst.id })
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.protocolId, origFirst.protocolId)
        XCTAssertEqual(reloaded?.dose, origFirst.dose)
        XCTAssertEqual(reloaded?.completed, origFirst.completed)
    }

    func test_saveAndLoadProfile_roundTrip() {
        let original = MockProfile.current
        persistence.saveProfile(original)

        let loaded = persistence.loadProfile()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.name, original.name)
        XCTAssertEqual(loaded!.goals, original.goals)
        XCTAssertEqual(loaded!.healthConnected, original.healthConnected)
        XCTAssertEqual(loaded!.hapticFeedbackEnabled, original.hapticFeedbackEnabled)
        XCTAssertEqual(loaded!.doseRemindersEnabled, original.doseRemindersEnabled)
        XCTAssertEqual(loaded!.biometricLockEnabled, original.biometricLockEnabled)
    }

    func test_loadProtocols_returnsNil_whenNoFile() {
        XCTAssertNil(persistence.loadProtocols())
    }

    func test_loadEntries_returnsNil_whenNoFile() {
        XCTAssertNil(persistence.loadEntries())
    }

    func test_loadProfile_returnsNil_whenNoFile() {
        XCTAssertNil(persistence.loadProfile())
    }

    // MARK: - Group 2: DataStore Init Path Tests

    func test_firstLaunch_emptyState() {
        let store = DataStore()
        XCTAssertTrue(store.protocols.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.profile.name, "")
        XCTAssertTrue(store.profile.goals.isEmpty)
    }

    func test_seedSampleData_populatesState() {
        let store = DataStore(seedSampleData: true)
        XCTAssertFalse(store.protocols.isEmpty)
        XCTAssertFalse(store.entries.isEmpty)
        XCTAssertEqual(store.profile.name, "Alex")
    }

    func test_returningUser_loadsPersistedData() {
        // Create store with seed data and let it save
        let original = DataStore(seedSampleData: true)
        let originalProtocolCount = original.protocols.count
        let originalProfileName = original.profile.name

        // Add a distinguishing protocol so we can verify it persisted
        let testProtocol = PeptideProtocol(
            id: UUID(),
            name: "Test Round-Trip Protocol",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 3, 5], timesPerDay: 1, preferredTimes: ["9:00 AM"]),
            cycleLengthWeeks: 4,
            startDate: Date(),
            status: .active,
            notes: "Created for round-trip test"
        )
        original.addProtocol(testProtocol)

        // Create a brand new DataStore — should load from persisted files
        let reloaded = DataStore()
        XCTAssertEqual(reloaded.protocols.count, originalProtocolCount + 1)
        XCTAssertTrue(reloaded.protocols.contains(where: { $0.name == "Test Round-Trip Protocol" }))
        XCTAssertEqual(reloaded.profile.name, originalProfileName)
    }

    func test_partialData_recoversWhatExists() {
        // Save only protocols (no entries, no profile) into SwiftData
        SwiftDataRepository.shared.saveProtocols(MockProtocols.all)

        let store = DataStore()
        XCTAssertEqual(store.protocols.count, MockProtocols.all.count)
        // No historical entries were saved, but regenerateTodayEntries() creates
        // today's schedule for active protocols on init.
        let historicalEntries = store.entries.filter {
            !Calendar.current.isDateInToday($0.date)
        }
        XCTAssertTrue(historicalEntries.isEmpty, "Should have no historical entries when no entries are in the store")
        XCTAssertEqual(store.profile.name, "", "Should use fresh profile when no profile is in the store")
    }

    // MARK: - Group 3: Codable Backward Compatibility

    func test_userProfile_decodesWithoutHapticField() throws {
        let json = """
        {
            "name": "Test",
            "goals": ["Recovery"],
            "memberSince": "2025-01-01T00:00:00Z",
            "healthConnected": false
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        XCTAssertTrue(profile.hapticFeedbackEnabled, "Should default to true when field is missing")
        XCTAssertFalse(profile.biometricLockEnabled, "Should default to false when field is missing")
    }

    func test_userProfile_decodesWithoutRemindersField() throws {
        let json = """
        {
            "name": "Test",
            "goals": [],
            "memberSince": "2025-01-01T00:00:00Z",
            "healthConnected": true
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        XCTAssertFalse(profile.doseRemindersEnabled, "Should default to false when field is missing")
    }

    func test_userProfile_decodesWithAllFields() throws {
        let json = """
        {
            "name": "Alex",
            "goals": ["Sleep", "Recovery"],
            "memberSince": "2025-06-15T12:00:00Z",
            "healthConnected": true,
            "hapticFeedbackEnabled": false,
            "doseRemindersEnabled": true,
            "biometricLockEnabled": true
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        XCTAssertEqual(profile.name, "Alex")
        XCTAssertEqual(profile.goals, ["Sleep", "Recovery"])
        XCTAssertTrue(profile.healthConnected)
        XCTAssertFalse(profile.hapticFeedbackEnabled, "Should respect explicit false")
        XCTAssertTrue(profile.doseRemindersEnabled, "Should respect explicit true")
        XCTAssertTrue(profile.biometricLockEnabled, "Should respect explicit true")
    }

    func test_userProfile_decodesWithoutCustomizationFields_defaultsAreSafe() throws {
        // A profile saved before the customization sheet shipped — no avatar,
        // no bio, no primaryGoal. Decoding must succeed and fall back cleanly.
        let json = """
        {
            "name": "Sam",
            "goals": ["Recovery"],
            "memberSince": "2025-01-01T00:00:00Z",
            "healthConnected": false
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        XCTAssertNil(profile.avatarImageData, "Missing avatar should decode to nil")
        XCTAssertEqual(profile.bio, "", "Missing bio should default to empty string")
        XCTAssertNil(profile.primaryGoal, "Missing primary goal should decode to nil")
    }

    func test_userProfile_codableRoundTrip_preservesCustomizationFields() throws {
        let original = UserProfile(
            name: "Casey",
            goals: ["Sleep", "Recovery"],
            memberSince: Date(timeIntervalSince1970: 1_700_000_000),
            healthConnected: false,
            avatarImageData: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
            bio: "Optimizing recovery and sleep.",
            primaryGoal: "Sleep"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.bio, original.bio)
        XCTAssertEqual(decoded.primaryGoal, original.primaryGoal)
        XCTAssertEqual(decoded.avatarImageData, original.avatarImageData)
    }

    func test_userProfile_emptyBio_roundTripsAsEmptyString() throws {
        // The DataStore trims bio on update; an empty bio shouldn't decode as
        // nil (the field is non-optional in the model).
        let original = UserProfile(
            name: "Alex",
            goals: [],
            memberSince: Date(),
            healthConnected: false,
            bio: ""
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.bio, "")
    }

    // MARK: - Group 4: StoredProfile (SwiftData) Migration

    func test_storedProfile_legacyRow_decodesWithEmptyCustomizationFields() throws {
        // Simulates a row written before avatarImageData / bio / primaryGoal
        // existed: nil columns. `toUserProfile` must produce a valid profile
        // with safe defaults so the customization sheet doesn't crash.
        let goalsData = try encoder.encode(["Recovery"])
        let stored = StoredProfile(
            name: "Legacy",
            memberSince: Date(timeIntervalSince1970: 1_700_000_000),
            healthConnected: false,
            hapticFeedbackEnabled: true,
            doseRemindersEnabled: false,
            biometricLockEnabled: false,
            goalsData: goalsData,
            bodyMetricsData: nil,
            avatarImageData: nil,
            bio: nil,
            primaryGoal: nil
        )

        let profile = try stored.toUserProfile()
        XCTAssertEqual(profile.name, "Legacy")
        XCTAssertEqual(profile.goals, ["Recovery"])
        XCTAssertNil(profile.avatarImageData)
        XCTAssertEqual(profile.bio, "")
        XCTAssertNil(profile.primaryGoal)
        XCTAssertEqual(profile.bodyMetrics.sex, .unspecified, "Missing metrics should fall back to .unspecified")
    }

    func test_storedProfile_make_preservesCustomizationFields() throws {
        let profile = UserProfile(
            name: "Casey",
            goals: ["Sleep", "Recovery"],
            memberSince: Date(),
            healthConnected: true,
            avatarImageData: Data([0x01, 0x02, 0x03]),
            bio: "Hello world",
            primaryGoal: "Sleep"
        )

        let stored = try StoredProfile.make(from: profile)
        XCTAssertEqual(stored.avatarImageData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(stored.bio, "Hello world")
        XCTAssertEqual(stored.primaryGoal, "Sleep")

        let roundTripped = try stored.toUserProfile()
        XCTAssertEqual(roundTripped.avatarImageData, profile.avatarImageData)
        XCTAssertEqual(roundTripped.bio, profile.bio)
        XCTAssertEqual(roundTripped.primaryGoal, profile.primaryGoal)
    }

    func test_storedProfile_make_collapsesEmptyBioToNil() throws {
        // Empty bio should serialize as nil in the SwiftData column to avoid
        // bloating the row with empty strings on every save.
        let profile = UserProfile(
            name: "Alex",
            goals: [],
            memberSince: Date(),
            healthConnected: false,
            bio: ""
        )

        let stored = try StoredProfile.make(from: profile)
        XCTAssertNil(stored.bio)
    }

    func test_researchLink_decodesWithoutOptionalFields() throws {
        let json = """
        {
            "title": "Study Title",
            "source": "Journal",
            "year": 2024
        }
        """.data(using: .utf8)!

        let link = try decoder.decode(ResearchLink.self, from: json)
        XCTAssertEqual(link.title, "Study Title")
        XCTAssertEqual(link.source, "Journal")
        XCTAssertEqual(link.year, 2024)
        XCTAssertEqual(link.pmid, "", "Should default to empty string")
        XCTAssertEqual(link.doi, "", "Should default to empty string")
        XCTAssertEqual(link.url, "", "Should default to empty string")
        XCTAssertNotEqual(link.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"), "Should generate a UUID")
    }

    func test_protocolEntry_roundTrip_withNilOptionals() throws {
        let entry = ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: makeSamplePeptide(),
            date: Date(),
            dose: "250 mcg",
            notes: "",
            completed: false,
            actualDose: nil,
            actualTime: nil,
            injectionSite: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProtocolEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.protocolId, entry.protocolId)
        XCTAssertEqual(decoded.dose, entry.dose)
        XCTAssertFalse(decoded.completed)
        XCTAssertNil(decoded.actualDose)
        XCTAssertNil(decoded.actualTime)
        XCTAssertNil(decoded.injectionSite)
    }

    func test_protocolEntry_roundTrip_withPopulatedOptionals() throws {
        let now = Date()
        let entry = ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: makeSamplePeptide(),
            date: now,
            dose: "500 mcg",
            notes: "Morning dose",
            completed: true,
            actualDose: "480 mcg",
            actualTime: now,
            injectionSite: "Left Deltoid"
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProtocolEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertTrue(decoded.completed)
        XCTAssertEqual(decoded.actualDose, "480 mcg")
        XCTAssertEqual(decoded.injectionSite, "Left Deltoid")
        XCTAssertNotNil(decoded.actualTime)
    }

    // MARK: - Group 4: DataStore Mutation Persistence

    func test_addProtocol_persistsAcrossRestart() {
        let store = DataStore(seedSampleData: true)
        let before = store.protocols.count

        let newProtocol = PeptideProtocol(
            id: UUID(),
            name: "Persisted Protocol",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5], timesPerDay: 1, preferredTimes: ["7:00 AM"]),
            cycleLengthWeeks: 6,
            startDate: Date(),
            status: .active,
            notes: ""
        )
        store.addProtocol(newProtocol)

        let reloaded = DataStore()
        XCTAssertEqual(reloaded.protocols.count, before + 1)
        XCTAssertTrue(reloaded.protocols.contains(where: { $0.name == "Persisted Protocol" }))
    }

    func test_deleteProtocol_persistsAcrossRestart() {
        let store = DataStore(seedSampleData: true)
        let target = store.protocols.first!
        let before = store.protocols.count

        store.deleteProtocol(id: target.id)

        let reloaded = DataStore()
        XCTAssertEqual(reloaded.protocols.count, before - 1)
        XCTAssertFalse(reloaded.protocols.contains(where: { $0.id == target.id }))
    }

    func test_toggleEntry_persistsAcrossRestart() {
        let store = DataStore(seedSampleData: true)

        guard let entry = store.todayEntries.first else {
            XCTFail("Seeded store should have today entries")
            return
        }

        let wasDone = entry.completed
        store.toggleEntry(entry.id)

        let reloaded = DataStore()
        let reloadedEntry = reloaded.entries.first(where: { $0.id == entry.id })
        XCTAssertNotNil(reloadedEntry)
        XCTAssertEqual(reloadedEntry!.completed, !wasDone)
    }

    func test_updateProfile_persistsAcrossRestart() {
        let store = DataStore(seedSampleData: true)
        store.updateGoals(Set(["Longevity", "Performance"]))

        let reloaded = DataStore()
        XCTAssertEqual(reloaded.profile.goals, ["Longevity", "Performance"])
    }

    // MARK: - Group 5: Edge Cases

    func test_emptyArrays_persistCorrectly() {
        persistence.saveProtocols([])
        persistence.saveEntries([])

        let protocols = persistence.loadProtocols()
        let entries = persistence.loadEntries()

        XCTAssertNotNil(protocols, "Should return empty array, not nil")
        XCTAssertNotNil(entries, "Should return empty array, not nil")
        XCTAssertEqual(protocols!.count, 0)
        XCTAssertEqual(entries!.count, 0)
    }

    func test_widgetData_roundTrip() throws {
        let original = WidgetData(
            nextPeptideName: "BPC-157",
            nextDose: "250 mcg",
            nextDoseTime: Date(),
            completedToday: 3,
            totalToday: 5,
            lastUpdated: Date()
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WidgetData.self, from: data)

        XCTAssertEqual(decoded.nextPeptideName, original.nextPeptideName)
        XCTAssertEqual(decoded.nextDose, original.nextDose)
        XCTAssertEqual(decoded.completedToday, original.completedToday)
        XCTAssertEqual(decoded.totalToday, original.totalToday)
        XCTAssertNotNil(decoded.nextDoseTime)
        XCTAssertEqual(decoded.compliance, 0.6, accuracy: 0.01)
    }

    func test_hasPersistedData_reflectsFileState() {
        XCTAssertFalse(persistence.hasPersistedData)
        persistence.saveProtocols([])
        XCTAssertTrue(persistence.hasPersistedData)
        persistence.clearAll()
        XCTAssertFalse(persistence.hasPersistedData)
    }

    // MARK: - Helpers

    private func makeSamplePeptide() -> Peptide {
        Peptide(
            name: "BPC-157",
            abbreviation: "BPC-157",
            category: .recovery,
            description: "Body Protection Compound",
            benefits: ["Recovery", "Healing"],
            dosageRange: "250-500 mcg",
            frequency: "1-2x daily",
            halfLife: "4 hours",
            adminRoute: "Subcutaneous",
            researchLinks: [],
            imageSystemName: "cross.vial.fill"
        )
    }
}
