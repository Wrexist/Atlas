import XCTest
@testable import Peptide

@MainActor
final class AchievementServiceTests: XCTestCase {

    private var service: AchievementService!
    private let testKey = "achievements_test"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "achievements")
        service = AchievementService.shared
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "achievements")
        service = nil
        super.tearDown()
    }

    // MARK: - Default state

    func test_defaultAchievements_areAllLocked() {
        XCTAssertEqual(service.unlockedCount, 0)
        XCTAssertEqual(service.totalCount, AchievementService.defaultAchievements.count)
        XCTAssertNil(service.latestUnlock)
    }

    func test_defaultAchievements_containsExpectedIDs() {
        let ids = Set(AchievementService.defaultAchievements.map(\.id))
        XCTAssertTrue(ids.contains("first_dose"))
        XCTAssertTrue(ids.contains("streak_7"))
        XCTAssertTrue(ids.contains("streak_90"))
        XCTAssertTrue(ids.contains("five_hundred_doses"))
        XCTAssertTrue(ids.contains("month_logged"))
    }

    // MARK: - Dose milestones

    func test_checkAchievements_oneDose_unlocksFirstDose() {
        service.checkAchievements(totalDoses: 1, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("first_dose")?.unlockedDate)
    }

    func test_checkAchievements_tenDoses_unlocksTenDoses() {
        service.checkAchievements(totalDoses: 10, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("ten_doses")?.unlockedDate)
    }

    func test_checkAchievements_fiftyDoses_unlocksFiftyDoses() {
        service.checkAchievements(totalDoses: 50, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("fifty_doses")?.unlockedDate)
    }

    func test_checkAchievements_ninetyNineDoses_doesNotUnlockHundred() {
        service.checkAchievements(totalDoses: 99, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNil(achievement("hundred_doses")?.unlockedDate)
    }

    func test_checkAchievements_fiveHundredDoses_unlocksLegendary() {
        service.checkAchievements(totalDoses: 500, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("five_hundred_doses")?.unlockedDate)
    }

    // MARK: - Streak milestones

    func test_checkAchievements_threeDayStreak_unlocksWarmingUp() {
        service.checkAchievements(totalDoses: 0, currentStreak: 3, bestStreak: 3, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("streak_3")?.unlockedDate)
    }

    func test_checkAchievements_sevenDayStreak_unlocksOnFire() {
        service.checkAchievements(totalDoses: 0, currentStreak: 7, bestStreak: 7, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("streak_7")?.unlockedDate)
    }

    func test_checkAchievements_ninetyDayStreak_unlocksMaster() {
        service.checkAchievements(totalDoses: 0, currentStreak: 90, bestStreak: 90, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("streak_90")?.unlockedDate)
    }

    func test_checkAchievements_sixDayStreak_doesNotUnlockStreakSeven() {
        service.checkAchievements(totalDoses: 0, currentStreak: 6, bestStreak: 6, protocolCount: 0, daysLogged: 0)
        XCTAssertNil(achievement("streak_7")?.unlockedDate)
    }

    // MARK: - Protocol & days milestones

    func test_checkAchievements_oneProtocol_unlocksProtocolCreator() {
        service.checkAchievements(totalDoses: 0, currentStreak: 0, bestStreak: 0, protocolCount: 1, daysLogged: 0)
        XCTAssertNotNil(achievement("first_protocol")?.unlockedDate)
    }

    func test_checkAchievements_sevenDaysLogged_unlocksWeekWarrior() {
        service.checkAchievements(totalDoses: 0, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 7)
        XCTAssertNotNil(achievement("week_logged")?.unlockedDate)
    }

    func test_checkAchievements_thirtyDaysLogged_unlocksMonthlyMaster() {
        service.checkAchievements(totalDoses: 0, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 30)
        XCTAssertNotNil(achievement("month_logged")?.unlockedDate)
    }

    // MARK: - Idempotency

    func test_checkAchievements_calledTwice_doesNotReLockOrDuplicate() {
        service.checkAchievements(totalDoses: 1, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        let firstUnlock = achievement("first_dose")?.unlockedDate

        service.checkAchievements(totalDoses: 1, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertEqual(achievement("first_dose")?.unlockedDate, firstUnlock)
        XCTAssertEqual(service.unlockedCount, 1)
    }

    func test_checkAchievements_secondCall_latestUnlockIsNilIfNothingNew() {
        service.checkAchievements(totalDoses: 1, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        service.checkAchievements(totalDoses: 1, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNil(service.latestUnlock)
    }

    // MARK: - latestUnlock

    func test_checkAchievements_newUnlock_setsLatestUnlock() {
        service.checkAchievements(totalDoses: 1, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertEqual(service.latestUnlock?.id, "first_dose")
    }

    func test_checkAchievements_noUnlock_latestUnlockIsNil() {
        service.checkAchievements(totalDoses: 0, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNil(service.latestUnlock)
    }

    // MARK: - Persistence

    func test_checkAchievements_persistsAcrossReload() {
        service.checkAchievements(totalDoses: 10, currentStreak: 0, bestStreak: 0, protocolCount: 0, daysLogged: 0)
        XCTAssertNotNil(achievement("ten_doses")?.unlockedDate)

        // Simulate app restart: clear and reload from defaults
        UserDefaults.standard.synchronize()
        let saved = UserDefaults.standard.data(forKey: "achievements")
        XCTAssertNotNil(saved, "Expected achievements to be persisted to UserDefaults")
        if let data = saved, let decoded = try? JSONDecoder().decode([Achievement].self, from: data) {
            let ten = decoded.first { $0.id == "ten_doses" }
            XCTAssertNotNil(ten?.unlockedDate)
        }
    }

    // MARK: - mergeWithDefaults

    func test_mergeWithDefaults_preservesExistingUnlocks() {
        var existing = AchievementService.defaultAchievements
        existing[0].unlockedDate = Date()
        let merged = AchievementService.defaultAchievements.map { def in
            if def.id == existing[0].id { return existing[0] }
            return def
        }
        XCTAssertNotNil(merged.first { $0.id == existing[0].id }?.unlockedDate)
    }

    // MARK: - Helpers

    private func achievement(_ id: String) -> Achievement? {
        service.achievements.first { $0.id == id }
    }
}
