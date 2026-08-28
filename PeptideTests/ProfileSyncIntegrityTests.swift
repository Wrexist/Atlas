import XCTest
@testable import Peptide

/// Multi-device safety of the profile store (audit Data Integrity 04,
/// Phases 3 + 8): high-churn feature areas live in their own
/// `StoredProfile` columns so CloudKit's field-level conflict
/// resolution can merge independent edits, and duplicate profile rows
/// reconcile deterministically instead of "whichever fetch returned
/// first".
///
/// True CloudKit sync cannot run in unit tests; these are the strongest
/// deterministic simulation — they assert the storage-level property
/// CloudKit's merge depends on (disjoint edits dirty disjoint columns)
/// and exercise the reconciliation path directly. The hardware
/// counterpart is docs/CLOUDKIT_HARDWARE_TEST_PLAN.md.
@MainActor
final class ProfileSyncIntegrityTests: XCTestCase {

    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
    }

    override func tearDown() {
        repo.deleteAll()
        repo = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func meal(_ name: String) -> MealEntry {
        MealEntry(date: day, category: .lunch, name: name,
                  calories: 550, proteinG: 40, carbsG: 50, fatG: 15,
                  source: .custom)
    }

    private func habit(_ name: String) -> Habit {
        Habit(name: name, iconSymbol: "drop.fill", tintHex: 0x33AAFF,
              createdAt: day)
    }

    private func baseProfile() -> UserProfile {
        var profile = UserProfile.fresh
        profile.name = "Sync Tester"
        profile.mealHistory = [meal("Base meal")]
        profile.habits = [habit("Hydrate")]
        return profile
    }

    // MARK: - Phase 3: field-level conflict surface

    /// Device A logs a meal, device B checks a habit. CloudKit merges
    /// per record field, so both facts survive iff the two edits dirty
    /// different columns while every untouched column stays
    /// byte-identical. This test asserts exactly that, then applies the
    /// merge CloudKit would produce and checks both facts came through.
    func test_multiDeviceConcurrentProfileEdit_bothFactsSurvive() throws {
        let base = baseProfile()

        var deviceA = base
        deviceA.mealHistory.append(meal("Device A salmon"))
        var deviceB = base
        deviceB.habitEntries.append(HabitEntry(habitId: base.habits[0].id, date: day))

        let rowBase = try StoredProfile.make(from: base)
        let rowA = try StoredProfile.make(from: deviceA)
        let rowB = try StoredProfile.make(from: deviceB)

        // A's edit dirties only the meals column…
        XCTAssertNotEqual(rowA.mealsData, rowBase.mealsData)
        XCTAssertEqual(rowA.habitsData, rowBase.habitsData,
                       "Logging a meal must not rewrite the habits column")
        XCTAssertEqual(rowA.extensionData, rowBase.extensionData,
                       "Logging a meal must not rewrite the residual blob")
        // …and B's only the habits column.
        XCTAssertNotEqual(rowB.habitsData, rowBase.habitsData)
        XCTAssertEqual(rowB.mealsData, rowBase.mealsData,
                       "Checking a habit must not rewrite the meals column")

        // CloudKit-style merge: take each device's dirty field.
        let merged = try StoredProfile.make(from: base)
        merged.mealsData = rowA.mealsData
        merged.habitsData = rowB.habitsData
        let reconciled = try merged.toUserProfile()

        XCTAssertTrue(reconciled.mealHistory.contains { $0.name == "Device A salmon" },
                      "Device A's meal must survive the merge")
        XCTAssertEqual(reconciled.habitEntries.count, 1,
                       "Device B's habit check-in must survive the merge")
    }

    /// The save path must not touch columns whose content didn't change —
    /// observable through `updatedAt`, which only advances on a real
    /// content change.
    func test_saveProfile_identicalContent_doesNotAdvanceUpdatedAt() throws {
        let profile = baseProfile()
        repo.saveProfile(profile)
        let firstStamp = try XCTUnwrap(loadStoredRow()).updatedAt

        repo.saveProfile(profile)
        XCTAssertEqual(try XCTUnwrap(loadStoredRow()).updatedAt, firstStamp,
                       "Re-saving unchanged content must not look like an edit")

        var edited = profile
        edited.name = "Renamed"
        repo.saveProfile(edited)
        XCTAssertGreaterThan(try XCTUnwrap(loadStoredRow()).updatedAt, firstStamp)
    }

    /// A row written before the split (slice columns nil, everything in
    /// the legacy blob) must surface its data unchanged, and the next
    /// save must move it into the split columns.
    func test_legacyBlobRow_readsThroughFallback_andMigratesOnNextSave() throws {
        struct LegacyExtension: Codable {
            var mealHistory: [MealEntry]
            var habits: [Habit]
            var atlasScore: Int
        }
        let legacy = LegacyExtension(
            mealHistory: [meal("Legacy meal")],
            habits: [habit("Legacy habit")],
            atlasScore: 420
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let row = try StoredProfile.make(from: .fresh)
        row.extensionData = try encoder.encode(legacy)
        row.mealsData = nil
        row.habitsData = nil
        row.momentumData = nil

        let decoded = try row.toUserProfile()
        XCTAssertEqual(decoded.mealHistory.first?.name, "Legacy meal")
        XCTAssertEqual(decoded.habits.first?.name, "Legacy habit")
        XCTAssertEqual(decoded.atlasScore, 420)

        try row.update(from: decoded)
        XCTAssertNotNil(row.mealsData, "A save must promote legacy blob data into the split columns")
        let roundTripped = try row.toUserProfile()
        XCTAssertEqual(roundTripped.mealHistory.first?.name, "Legacy meal")
        XCTAssertEqual(roundTripped.atlasScore, 420)
    }

    // MARK: - Phase 8: singleton identity + reconciliation

    func test_firstSave_createsExactlyOneRow_withSingletonKey() throws {
        repo.saveProfile(baseProfile())
        let rows = try fetchAllRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.singletonKey, StoredProfile.canonicalSingletonKey)
    }

    func test_duplicateProfileRows_reconcileToNewest_andAdoptMissingSlices() throws {
        // Simulate two devices that each created a row before CloudKit
        // converged: the older row carries habits the newer lacks.
        var older = baseProfile()
        older.name = "Older device"
        let olderRow = try StoredProfile.make(from: older)
        olderRow.updatedAt = day

        var newer = UserProfile.fresh
        newer.name = "Newer device"
        let newerRow = try StoredProfile.make(from: newer)
        newerRow.habitsData = nil   // newer device never had habits
        newerRow.updatedAt = day.addingTimeInterval(3600)

        try insertRows([olderRow, newerRow])

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.name, "Newer device", "Newest row must win deterministically")
        XCTAssertEqual(loaded.habits.first?.name, "Hydrate",
                       "A slice the winner lacks must be adopted from the losing row")
        XCTAssertEqual(try fetchAllRows().count, 1,
                       "Reconciliation must converge to a single row")
    }

    func test_reload_returnsSameProfile_afterReconciliation() throws {
        repo.saveProfile(baseProfile())
        let first = try XCTUnwrap(repo.loadProfile())
        let second = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(first.name, second.name)
        XCTAssertEqual(first.mealHistory, second.mealHistory)
        XCTAssertEqual(try fetchAllRows().count, 1)
    }

    // MARK: - Helpers

    private func loadStoredRow() throws -> StoredProfile? {
        try fetchAllRows().first
    }

    private func fetchAllRows() throws -> [StoredProfile] {
        try XCTUnwrap(repo.contextForTesting)
            .fetch(FetchDescriptor<StoredProfile>())
    }

    private func insertRows(_ rows: [StoredProfile]) throws {
        let context = try XCTUnwrap(repo.contextForTesting)
        for row in rows { context.insert(row) }
        try context.save()
    }
}
