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

    func test_userProfile_codableRoundTrip_preservesCustomFoodsAndFavorites() throws {
        let nutrients = ScannedProduct.Nutriments(
            calories: 250,
            proteinG: 18,
            carbsG: 30,
            fatG: 6,
            fiberG: 4,
            sugarsG: 5
        )
        let custom = CustomFood(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Mum's lasagna",
            brand: "Home",
            per100g: nutrients,
            servingGrams: 250,
            servingLabel: "1 portion"
        )
        let original = UserProfile(
            name: "Casey",
            goals: ["Sleep"],
            memberSince: Date(timeIntervalSince1970: 1_700_000_000),
            healthConnected: false,
            customFoods: [custom],
            favoriteFoodIDs: ["5449000000996", custom.foodID]
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.customFoods.count, 1)
        XCTAssertEqual(decoded.customFoods.first?.name, "Mum's lasagna")
        XCTAssertEqual(decoded.customFoods.first?.per100g.calories, 250)
        XCTAssertEqual(decoded.customFoods.first?.servingGrams, 250)
        XCTAssertTrue(decoded.favoriteFoodIDs.contains("5449000000996"))
        XCTAssertTrue(decoded.favoriteFoodIDs.contains(custom.foodID))
    }

    func test_logMealEntry_appendsHistoryAndUpdatesAggregateInLockstep() throws {
        var profile = UserProfile.fresh
        let entry = MealEntry(
            date: Date(),
            category: .lunch,
            name: "Chicken bowl",
            calories: 500,
            proteinG: 40,
            carbsG: 50,
            fatG: 15,
            sourceID: "5449000000996",
            source: .openFoodFacts
        )
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry)

        XCTAssertEqual(profile.mealHistory.count, 1)
        let today = LifestyleDataLogic.consumption(in: profile, for: Date())
        XCTAssertEqual(today.caloriesKcal, 500)
        XCTAssertEqual(today.proteinG, 40)
        XCTAssertEqual(today.carbsG, 50)
        XCTAssertEqual(today.fatG, 15)
    }

    func test_unlogMealEntry_rollsBackAggregateAndRemovesEntry() throws {
        var profile = UserProfile.fresh
        let entry = MealEntry(
            date: Date(),
            category: .dinner,
            name: "Salmon",
            calories: 400,
            proteinG: 35,
            carbsG: 0,
            fatG: 25,
            source: .photo
        )
        LifestyleDataLogic.logMealEntry(into: &profile, entry: entry)
        LifestyleDataLogic.unlogMealEntry(from: &profile, id: entry.id)

        XCTAssertTrue(profile.mealHistory.isEmpty)
        let today = LifestyleDataLogic.consumption(in: profile, for: Date())
        XCTAssertEqual(today.caloriesKcal, 0)
        XCTAssertEqual(today.proteinG, 0)
    }

    func test_mealsByCategory_bucketsEntriesAndCapturesLegacyAggregateAsOther() throws {
        var profile = UserProfile.fresh
        let breakfast = MealEntry(
            date: Date(), category: .breakfast, name: "Oats",
            calories: 300, proteinG: 12, carbsG: 50, fatG: 5, source: .custom
        )
        let dinner = MealEntry(
            date: Date(), category: .dinner, name: "Steak",
            calories: 600, proteinG: 45, carbsG: 0, fatG: 35, source: .openFoodFacts
        )
        LifestyleDataLogic.logMealEntry(into: &profile, entry: breakfast)
        LifestyleDataLogic.logMealEntry(into: &profile, entry: dinner)
        // Simulate a legacy aggregate-only log (no MealEntry) — e.g.
        // a meal logged before this branch shipped.
        LifestyleDataLogic.logMeal(
            into: &profile,
            calories: 200, proteinG: 5, carbsG: 30, fatG: 4,
            date: Date()
        )

        let breakdown = LifestyleDataLogic.mealsByCategory(in: profile, for: Date())
        XCTAssertEqual(breakdown.breakfast.calories, 300)
        XCTAssertEqual(breakdown.breakfast.entryCount, 1)
        XCTAssertEqual(breakdown.dinner.calories, 600)
        XCTAssertEqual(breakdown.lunch.calories, 0)
        XCTAssertEqual(breakdown.snack.calories, 0)
        XCTAssertEqual(breakdown.other.calories, 200)
        XCTAssertEqual(breakdown.totalCalories, 1100)
    }

    func test_mealCategory_autoForDate_picksByHour() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let morning = cal.date(byAdding: .hour, value: 8, to: today)!
        let noon    = cal.date(byAdding: .hour, value: 12, to: today)!
        let evening = cal.date(byAdding: .hour, value: 18, to: today)!
        let lateNight = cal.date(byAdding: .hour, value: 23, to: today)!
        XCTAssertEqual(MealCategory.auto(for: morning), .breakfast)
        XCTAssertEqual(MealCategory.auto(for: noon),    .lunch)
        XCTAssertEqual(MealCategory.auto(for: evening), .dinner)
        XCTAssertEqual(MealCategory.auto(for: lateNight), .snack)
    }

    func test_updateMealEntry_changesCategoryWithoutShiftingAggregate() throws {
        var profile = UserProfile.fresh
        let original = MealEntry(
            date: Date(),
            category: .lunch,
            name: "Chicken",
            calories: 400,
            proteinG: 35,
            carbsG: 10,
            fatG: 15,
            source: .openFoodFacts
        )
        LifestyleDataLogic.logMealEntry(into: &profile, entry: original)
        let before = LifestyleDataLogic.consumption(in: profile, for: Date())

        // Recategorize same entry — aggregate must not move because
        // only the category bucket changed.
        var updated = original
        updated.category = .dinner
        if let index = profile.mealHistory.firstIndex(where: { $0.id == original.id }) {
            profile.mealHistory[index] = updated
        }
        let after = LifestyleDataLogic.consumption(in: profile, for: Date())
        XCTAssertEqual(before.caloriesKcal, after.caloriesKcal)

        let breakdown = LifestyleDataLogic.mealsByCategory(in: profile, for: Date())
        XCTAssertEqual(breakdown.lunch.calories, 0)
        XCTAssertEqual(breakdown.dinner.calories, 400)
    }

    func test_mealLoggingStreak_countsConsecutiveDaysEndingToday() {
        var profile = UserProfile.fresh
        let today = Calendar.current.startOfDay(for: Date())
        for daysAgo in 0...4 {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
            profile.mealHistory.append(
                MealEntry(date: date, category: .lunch, name: "Lunch",
                          calories: 400, proteinG: 30, carbsG: 40, fatG: 10,
                          source: .openFoodFacts)
            )
        }
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: profile, asOf: today), 5)
    }

    func test_mealLoggingStreak_breaksOnTwoConsecutiveEmptyDays() {
        var profile = UserProfile.fresh
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Logged 4 days ago and 5 days ago — both today and yesterday
        // are empty, so the streak should read 0.
        for daysAgo in [4, 5] {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            profile.mealHistory.append(
                MealEntry(date: date, category: .dinner, name: "Dinner",
                          calories: 500, proteinG: 40, carbsG: 0, fatG: 20,
                          source: .photo)
            )
        }
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: profile, asOf: today), 0)
    }

    func test_mealLoggingStreak_graceDayWhenTodayIsEmpty() {
        // Today empty, yesterday logged, two days ago logged. Streak
        // should be 2 — today gets a grace pass until the user logs
        // something or the day ends.
        var profile = UserProfile.fresh
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for daysAgo in [1, 2] {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            profile.mealHistory.append(
                MealEntry(date: date, category: .breakfast, name: "Oats",
                          calories: 300, proteinG: 12, carbsG: 50, fatG: 5,
                          source: .custom)
            )
        }
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: profile, asOf: today), 2)
    }

    func test_bestMealLoggingStreak_findsLongestRunHistorically() {
        var profile = UserProfile.fresh
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Three distinct runs of consecutive logged days:
        //   • 60-50 days ago = 11 consecutive days (longest run)
        //   • 35-30 days ago = 6 consecutive days
        //   • today only = active 1-day streak
        let runs: [[Int]] = [
            Array(50...60),  // 11 days
            Array(30...35),  //  6 days
            [0],             //  1 day (today)
        ]
        for run in runs {
            for daysAgo in run {
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
                profile.mealHistory.append(
                    MealEntry(date: date, category: .snack, name: "Snack",
                              calories: 100, proteinG: 5, carbsG: 15, fatG: 3,
                              source: .openFoodFacts)
                )
            }
        }
        XCTAssertEqual(LifestyleDataLogic.bestMealLoggingStreak(in: profile, asOf: today), 11)
    }

    func test_spotlightIdentifier_roundTrips_throughDeepLink() throws {
        let customID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let customIdentifier = FoodSpotlightService.identifier(forCustomFoodID: customID)
        let parsedCustom = FoodLogDeepLink(spotlightIdentifier: customIdentifier)
        XCTAssertEqual(parsedCustom, .custom(id: customID))

        let barcode = "5449000000996"
        let offIdentifier = FoodSpotlightService.identifier(forBarcode: barcode)
        let parsedOFF = FoodLogDeepLink(spotlightIdentifier: offIdentifier)
        XCTAssertEqual(parsedOFF, .openFoodFacts(barcode: barcode))

        // Garbage strings return nil, not a crash.
        XCTAssertNil(FoodLogDeepLink(spotlightIdentifier: "not-a-peptidex-identifier"))
        XCTAssertNil(FoodLogDeepLink(spotlightIdentifier: "peptidex-food/wrong/123"))
        XCTAssertNil(FoodLogDeepLink(spotlightIdentifier: "peptidex-food/custom/not-a-uuid"))
    }

    func test_logOutcome_oneEntryPerDayReplacesPrior() {
        var profile = UserProfile.fresh
        let today = Date()
        let first = OutcomeEntry(
            date: today, energy: 3, sleepQuality: 3, recovery: 3,
            mood: 3, focus: 3, note: "first take"
        )
        LifestyleDataLogic.logOutcome(into: &profile, entry: first)
        XCTAssertEqual(profile.outcomeHistory.count, 1)
        XCTAssertEqual(profile.outcomeHistory.first?.note, "first take")

        // Same day, different scores — should overwrite, not duplicate.
        let revised = OutcomeEntry(
            date: today, energy: 5, sleepQuality: 4, recovery: 4,
            mood: 5, focus: 5, note: "second take"
        )
        LifestyleDataLogic.logOutcome(into: &profile, entry: revised)
        XCTAssertEqual(profile.outcomeHistory.count, 1)
        XCTAssertEqual(profile.outcomeHistory.first?.energy, 5)
        XCTAssertEqual(profile.outcomeHistory.first?.note, "second take")
    }

    func test_correlationEngine_findsDoseDayDelta_whenSamplesSufficient() {
        // 5 dosing days with high energy, 5 off days with low — engine
        // should pick up a positive delta on .energy.
        var profile = UserProfile.fresh
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var entries: [ProtocolEntry] = []

        for daysAgo in 0...9 {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let isDosingDay = daysAgo.isMultiple(of: 2)
            profile.outcomeHistory.append(
                OutcomeEntry(
                    date: date,
                    energy: isDosingDay ? 5 : 2,
                    sleepQuality: 3,
                    recovery: 3,
                    mood: 3,
                    focus: 3
                )
            )
            if isDosingDay {
                entries.append(ProtocolEntry(
                    id: UUID(),
                    protocolId: UUID(),
                    peptide: MockPeptides.bpc157,
                    date: date,
                    dose: "250 mcg",
                    notes: "",
                    completed: true,
                    actualDose: nil,
                    actualTime: nil,
                    injectionSite: nil
                ))
            }
        }

        let headline = OutcomeCorrelationEngine.headline(
            outcomes: profile.outcomeHistory,
            entries: entries
        )
        let resolved = try? XCTUnwrap(headline)
        XCTAssertEqual(resolved?.dimension, .energy)
        XCTAssertGreaterThan(resolved?.delta ?? 0, 2.5)
    }

    func test_correlationEngine_returnsNil_whenSamplesInsufficient() {
        // Only 2 dosing days — below the minimum sample threshold,
        // so headline should be nil regardless of how strong the
        // delta would have been.
        var profile = UserProfile.fresh
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var entries: [ProtocolEntry] = []
        for daysAgo in 0...2 {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            profile.outcomeHistory.append(
                OutcomeEntry(
                    date: date,
                    energy: daysAgo == 0 ? 5 : 1,
                    sleepQuality: 3, recovery: 3, mood: 3, focus: 3
                )
            )
            if daysAgo == 0 {
                entries.append(ProtocolEntry(
                    id: UUID(),
                    protocolId: UUID(),
                    peptide: MockPeptides.bpc157,
                    date: date,
                    dose: "250 mcg",
                    notes: "",
                    completed: true,
                    actualDose: nil,
                    actualTime: nil,
                    injectionSite: nil
                ))
            }
        }
        XCTAssertNil(OutcomeCorrelationEngine.headline(
            outcomes: profile.outcomeHistory,
            entries: entries
        ))
    }

    func test_saveLabValue_replacesByIdAndSortsNewestFirst() {
        var profile = UserProfile.fresh
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let id = UUID()

        let v1 = LabValue(
            id: id, date: today, panel: .totalTestosterone, value: 600
        )
        let oldDate = calendar.date(byAdding: .day, value: -30, to: today)!
        let v2 = LabValue(
            date: oldDate, panel: .totalTestosterone, value: 480
        )
        LabDataLogic.saveLabValue(into: &profile, value: v1)
        LabDataLogic.saveLabValue(into: &profile, value: v2)
        XCTAssertEqual(profile.labHistory.count, 2)
        XCTAssertEqual(profile.labHistory.first?.id, id, "Newest entry should sort first")

        // Update v1's value — should replace, not duplicate.
        let v1Revised = LabValue(
            id: id, date: today, panel: .totalTestosterone, value: 720
        )
        LabDataLogic.saveLabValue(into: &profile, value: v1Revised)
        XCTAssertEqual(profile.labHistory.count, 2)
        XCTAssertEqual(profile.labHistory.first?.value, 720)
    }

    func test_labTrend_stable_belowFivePercentDelta() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let prev = LabValue(
            date: calendar.date(byAdding: .day, value: -30, to: today)!,
            panel: .totalTestosterone, value: 600
        )
        let nextWithin = LabValue(
            date: today, panel: .totalTestosterone, value: 620   // ~3.3% delta
        )
        XCTAssertEqual(LabDataLogic.computeTrend(entries: [prev, nextWithin]), .stable)

        let nextRising = LabValue(
            date: today, panel: .totalTestosterone, value: 720   // 20% delta
        )
        if case .rising(let delta) = LabDataLogic.computeTrend(entries: [prev, nextRising]) {
            XCTAssertEqual(delta, 120, accuracy: 0.01)
        } else {
            XCTFail("Expected rising trend for +20% delta")
        }
    }

    func test_latestPerPanel_returnsMostRecentPerPanelAndPreservesCategoryOrder() {
        var profile = UserProfile.fresh
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        LabDataLogic.saveLabValue(into: &profile, value:
            LabValue(date: yesterday, panel: .totalTestosterone, value: 480)
        )
        LabDataLogic.saveLabValue(into: &profile, value:
            LabValue(date: today, panel: .totalTestosterone, value: 720)
        )
        LabDataLogic.saveLabValue(into: &profile, value:
            LabValue(date: today, panel: .igf1, value: 220)
        )

        let summaries = LabDataLogic.latestPerPanel(in: profile)
        XCTAssertEqual(summaries.count, 2)
        let tt = summaries.first(where: { $0.latest.panel == .totalTestosterone })
        XCTAssertEqual(tt?.latest.value, 720, "Most recent value should win")
    }

    func test_cyclePhaseEngine_singleCycle_progressesThenCompletes() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let proto = PeptideProtocol(
            id: UUID(),
            name: "BPC",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: 1,
                preferredTimes: ["8:00 AM"]
            ),
            cycleLengthWeeks: 4,
            washoutWeeks: 0,
            startDate: start,
            status: .active,
            notes: ""
        )

        // Day 1 in.
        let day1 = CyclePhaseEngine.status(for: proto, at: start)
        if case .onCycle(let d, let t) = day1.phase {
            XCTAssertEqual(d, 1)
            XCTAssertEqual(t, 28)
        } else { XCTFail("Expected onCycle on day 1") }

        // Past the end — single-cycle path completes (no washout).
        let after = calendar.date(byAdding: .day, value: 30, to: start)!
        XCTAssertEqual(CyclePhaseEngine.status(for: proto, at: after).phase, .completed)
    }

    func test_cyclePhaseEngine_repeatingCycle_alternatesOnAndWashout() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let proto = PeptideProtocol(
            id: UUID(),
            name: "BPC cycled",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: 1,
                preferredTimes: ["8:00 AM"]
            ),
            cycleLengthWeeks: 4,       // 28 days on
            washoutWeeks: 2,           // 14 days off
            startDate: start,
            status: .active,
            notes: ""
        )

        // Day 1: onCycle, cycle 1.
        if case .onCycle(let d, _) = CyclePhaseEngine.status(for: proto, at: start).phase {
            XCTAssertEqual(d, 1)
        } else { XCTFail("Expected onCycle on day 1") }

        // Day 30: 28 days on done + 2 days into wash-out.
        let day30 = calendar.date(byAdding: .day, value: 29, to: start)!
        let phaseDay30 = CyclePhaseEngine.status(for: proto, at: day30)
        if case .washout(let d, let t) = phaseDay30.phase {
            XCTAssertEqual(d, 2)
            XCTAssertEqual(t, 14)
        } else { XCTFail("Expected washout on day 30") }
        XCTAssertEqual(phaseDay30.cycleNumber, 1)

        // Day 43: 28+14 = 42 days completed → onCycle day 1 of cycle 2.
        let day43 = calendar.date(byAdding: .day, value: 42, to: start)!
        let phaseDay43 = CyclePhaseEngine.status(for: proto, at: day43)
        if case .onCycle(let d, _) = phaseDay43.phase {
            XCTAssertEqual(d, 1)
        } else { XCTFail("Expected onCycle on day 43") }
        XCTAssertEqual(phaseDay43.cycleNumber, 2)
    }

    func test_cyclePhaseEngine_beforeStart_reportsUpcoming() {
        let calendar = Calendar.current
        let futureStart = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: Date()))!
        let proto = PeptideProtocol(
            id: UUID(),
            name: "Future",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: 1,
                preferredTimes: ["8:00 AM"]
            ),
            cycleLengthWeeks: 4,
            washoutWeeks: 0,
            startDate: futureStart,
            status: .active,
            notes: ""
        )
        if case .upcoming(let days) = CyclePhaseEngine.status(for: proto).phase {
            XCTAssertEqual(days, 5)
        } else { XCTFail("Expected upcoming") }
    }

    func test_progressPhotoMetadata_parsesUnixTimestampFromFilename() {
        // Filename format: progress-<unix>-<uuid6>.jpg
        let stamp: TimeInterval = 1_715_000_000   // May 2024
        let filename = "progress-\(Int(stamp))-abc123.jpg"
        let parsed = ProgressPhotoMetadata.date(forFilename: filename)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timeIntervalSince1970, stamp, accuracy: 0.001)
    }

    func test_progressPhotoMetadata_returnsNilForUnknownScheme() {
        XCTAssertNil(ProgressPhotoMetadata.date(forFilename: "IMG_1234.jpg"))
        XCTAssertNil(ProgressPhotoMetadata.date(forFilename: "progress-not-a-number-abc.jpg"))
    }

    func test_progressPhotoMetadata_daysBetween_isAbsoluteAndDayResolution() {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let earlier = cal.date(byAdding: .day, value: -10, to: now)!
        let fnA = "progress-\(Int(now.timeIntervalSince1970))-aaa111.jpg"
        let fnB = "progress-\(Int(earlier.timeIntervalSince1970))-bbb222.jpg"
        XCTAssertEqual(ProgressPhotoMetadata.daysBetween(fnA, fnB), 10)
        XCTAssertEqual(ProgressPhotoMetadata.daysBetween(fnB, fnA), 10, "Should be absolute")
    }

    func test_timezoneDetector_returnsNilWhenIdentifiersMatch() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertNil(TimezoneChangeDetector.detect(
            previousIdentifier: zone.identifier,
            currentZone: zone
        ))
    }

    func test_timezoneDetector_detectsHourCrossingWithSignedDelta() {
        // LA → NY: +3 hours (clock moves forward by 3).
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let ny = TimeZone(identifier: "America/New_York")!
        let change = TimezoneChangeDetector.detect(
            previousIdentifier: la.identifier,
            currentZone: ny
        )
        XCTAssertNotNil(change)
        XCTAssertEqual(change?.hoursDelta, 3)
        XCTAssertEqual(change?.minutesRemainder, 0)
    }

    func test_timezoneDetector_includesMinuteRemainderForOffsetZones() {
        // LA → Mumbai: +12:30 ahead in standard time terms.
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let mumbai = TimeZone(identifier: "Asia/Kolkata")!
        let change = TimezoneChangeDetector.detect(
            previousIdentifier: la.identifier,
            currentZone: mumbai,
            at: Date(timeIntervalSince1970: 1_715_000_000)
        )
        XCTAssertNotNil(change)
        XCTAssertEqual(abs(change!.minutesRemainder), 30)
    }

    func test_travelModeLogic_shiftsPreferredTimes() {
        let original = "8:00 AM"
        let shifted = TravelModeLogic.shiftTime(original, byHours: 3)
        XCTAssertEqual(shifted, "11:00 AM")

        let crossNoon = TravelModeLogic.shiftTime("11:00 AM", byHours: 5)
        XCTAssertEqual(crossNoon, "4:00 PM")

        // Negative shift (travelled west, clock moves back).
        XCTAssertEqual(TravelModeLogic.shiftTime("11:00 AM", byHours: -3), "8:00 AM")
    }

    func test_streakFreeze_isLimitedToOnePerMonth() {
        var profile = UserProfile.fresh
        let today = Date()
        XCTAssertTrue(StreakFreezeService.hasFreezeAvailable(in: profile, now: today))

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        XCTAssertTrue(StreakFreezeService.applyFreeze(in: &profile, for: yesterday, now: today))
        XCTAssertFalse(StreakFreezeService.hasFreezeAvailable(in: profile, now: today))

        // Second freeze in the same month is rejected.
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        XCTAssertFalse(StreakFreezeService.applyFreeze(in: &profile, for: twoDaysAgo, now: today))
    }

    func test_streakFreeze_shieldsMissedDay() {
        // Logged today + 2 days ago. Yesterday is missing — without
        // a freeze the streak would break, with one it survives.
        var profile = UserProfile.fresh
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        for day in [today, twoDaysAgo] {
            profile.mealHistory.append(MealEntry(
                date: day, category: .lunch, name: "Lunch",
                calories: 400, proteinG: 30, carbsG: 40, fatG: 10,
                source: .openFoodFacts
            ))
        }
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: profile, asOf: today), 1,
                       "Yesterday gap should break the streak when no freeze is applied")

        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        _ = StreakFreezeService.applyFreeze(in: &profile, for: yesterday, now: today)
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: profile, asOf: today), 3,
                       "Freeze should bridge the gap and extend the streak across 3 days")
    }

    func test_biometricCorrelation_findsPositiveHRVDelta() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var hrvSeries: [(Date, Double)] = []
        var entries: [ProtocolEntry] = []

        for daysAgo in 0..<14 {
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let isDosing = daysAgo.isMultiple(of: 2)
            // Dosing days: 65 ms HRV. Off days: 50 ms.
            hrvSeries.append((date, isDosing ? 65 : 50))
            if isDosing {
                entries.append(ProtocolEntry(
                    id: UUID(), protocolId: UUID(),
                    peptide: MockPeptides.bpc157, date: date,
                    dose: "250 mcg", notes: "",
                    completed: true, actualDose: nil,
                    actualTime: nil, injectionSite: nil
                ))
            }
        }

        let findings = BiometricCorrelationEngine.correlations(
            seriesByMetric: [.hrv: hrvSeries],
            entries: entries
        )
        XCTAssertEqual(findings.count, 1)
        let finding = try? XCTUnwrap(findings.first)
        XCTAssertEqual(finding?.metric, .hrv)
        XCTAssertEqual(finding?.delta ?? 0, 15, accuracy: 0.001)
        XCTAssertTrue(finding?.isFavourable ?? false)

        let headline = BiometricCorrelationEngine.headline(from: findings)
        XCTAssertEqual(headline?.metric, .hrv)
    }

    func test_biometricCorrelation_dropsBelowSampleThreshold() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Only 3 dosing days — below the 4-per-bucket minimum.
        var hrvSeries: [(Date, Double)] = []
        var entries: [ProtocolEntry] = []
        for daysAgo in 0..<3 {
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            hrvSeries.append((date, 100))   // huge effect
            entries.append(ProtocolEntry(
                id: UUID(), protocolId: UUID(),
                peptide: MockPeptides.bpc157, date: date,
                dose: "250 mcg", notes: "",
                completed: true, actualDose: nil,
                actualTime: nil, injectionSite: nil
            ))
        }
        let findings = BiometricCorrelationEngine.correlations(
            seriesByMetric: [.hrv: hrvSeries],
            entries: entries
        )
        XCTAssertTrue(findings.isEmpty, "Should suppress until 4 days per bucket exist")
    }

    func test_biometricMetric_directionOfGood_drivesFavourabilityCorrectly() {
        // RHR is "lower is better". A negative delta on a dosing
        // day should be favourable; positive (RHR went up) should
        // not surface as a headline.
        let bad = BiometricCorrelationEngine.Finding(
            metric: .restingHeartRate,
            onDoseDays: 65, offDoseDays: 60,    // RHR is HIGHER on dose days
            doseDayCount: 7, offDayCount: 7
        )
        XCTAssertFalse(bad.isFavourable)

        let good = BiometricCorrelationEngine.Finding(
            metric: .restingHeartRate,
            onDoseDays: 55, offDoseDays: 60,    // RHR is LOWER on dose days
            doseDayCount: 7, offDayCount: 7
        )
        XCTAssertTrue(good.isFavourable)
        XCTAssertNotNil(BiometricCorrelationEngine.headline(from: [bad, good]))
    }

    func test_recipeTotals_sumsResolvedComponents() {
        let oats = CustomFood(
            name: "Oats", per100g: ScannedProduct.Nutriments(
                calories: 380, proteinG: 13, carbsG: 67, fatG: 7, fiberG: 10, sugarsG: 1
            ),
            servingGrams: nil
        )
        let banana = CustomFood(
            name: "Banana", per100g: ScannedProduct.Nutriments(
                calories: 89, proteinG: 1, carbsG: 23, fatG: 0, fiberG: 3, sugarsG: 12
            ),
            servingGrams: nil
        )
        // 80g oats + 100g banana
        let recipe = Recipe(
            name: "Morning bowl",
            components: [
                Recipe.Component(foodID: oats.foodID, cachedName: "Oats", portion: .grams(80)),
                Recipe.Component(foodID: banana.foodID, cachedName: "Banana", portion: .grams(100)),
            ]
        )
        let totals = RecipeDataLogic.totals(
            for: recipe,
            customFoods: [oats, banana]
        )
        // 380 * 0.8 = 304 + 89 = 393. Allow ±1 for rounding.
        XCTAssertEqual(totals.calories, 393, accuracy: 1)
        XCTAssertEqual(totals.proteinG, 11, accuracy: 1)
    }

    func test_recipeTotals_skipsMissingComponentsWithoutCrashing() {
        let oats = CustomFood(
            name: "Oats", per100g: ScannedProduct.Nutriments(
                calories: 380, proteinG: 13, carbsG: 67, fatG: 7, fiberG: nil, sugarsG: nil
            )
        )
        // Reference a foodID that isn't in the customFoods list —
        // simulates a deleted custom food. Should drop to 0
        // contribution, not crash.
        let recipe = Recipe(
            name: "Half-broken",
            components: [
                Recipe.Component(foodID: oats.foodID, cachedName: "Oats", portion: .grams(100)),
                Recipe.Component(foodID: "custom:99999999-9999-9999-9999-999999999999", cachedName: "Ghost", portion: .grams(50)),
            ]
        )
        let totals = RecipeDataLogic.totals(for: recipe, customFoods: [oats])
        XCTAssertEqual(totals.calories, 380)   // only the oats contributed
    }

    func test_saveRecipe_replacesById_andSortsByUpdatedAt() {
        var profile = UserProfile.fresh
        let id = UUID()
        let initial = Recipe(id: id, name: "First")
        let other = Recipe(name: "Other")
        RecipeDataLogic.saveRecipe(into: &profile, recipe: initial)
        RecipeDataLogic.saveRecipe(into: &profile, recipe: other)
        XCTAssertEqual(profile.recipes.count, 2)
        XCTAssertEqual(profile.recipes.first?.id, other.id, "Newest by updatedAt sorts first")

        let revised = Recipe(id: id, name: "First (renamed)")
        RecipeDataLogic.saveRecipe(into: &profile, recipe: revised)
        XCTAssertEqual(profile.recipes.count, 2, "Should replace by id, not duplicate")
        XCTAssertEqual(profile.recipes.first?.id, id, "Just-edited recipe sorts back to top")
    }

    func test_recipeSpotlightIdentifier_roundTripsThroughDeepLink() {
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let identifier = FoodSpotlightService.identifier(forRecipeID: id)
        XCTAssertEqual(identifier, "peptidex-food/recipe/\(id.uuidString)")
        let parsed = FoodLogDeepLink(spotlightIdentifier: identifier)
        XCTAssertEqual(parsed, .recipe(id: id))
    }

    func test_offRateLimiter_allowsUpToCapThenDenies() async {
        // 3 calls / 60-second window — easier to assert than the
        // production 8/60s config without changing the algorithm.
        let limiter = OFFRateLimiter(maxRequests: 3, windowSeconds: 60)
        let now = Date()
        let a = await limiter.requestSlot(now: now)
        let b = await limiter.requestSlot(now: now.addingTimeInterval(1))
        let c = await limiter.requestSlot(now: now.addingTimeInterval(2))
        let d = await limiter.requestSlot(now: now.addingTimeInterval(3))
        XCTAssertEqual(a, .allowed)
        XCTAssertEqual(b, .allowed)
        XCTAssertEqual(c, .allowed)
        if case .denied(let retry) = d {
            XCTAssertGreaterThanOrEqual(retry, 1)
            XCTAssertLessThanOrEqual(retry, 60)
        } else {
            XCTFail("Expected fourth call to be denied")
        }
    }

    func test_offRateLimiter_releasesSlotAfterWindowExpires() async {
        let limiter = OFFRateLimiter(maxRequests: 2, windowSeconds: 30)
        let t0 = Date()
        _ = await limiter.requestSlot(now: t0)
        _ = await limiter.requestSlot(now: t0.addingTimeInterval(1))
        // Inside the window — should still be denied.
        let stillFull = await limiter.requestSlot(now: t0.addingTimeInterval(15))
        guard case .denied = stillFull else {
            XCTFail("Expected denied at t+15s inside the 30s window")
            return
        }
        // Past the window — oldest slot has aged out, next call passes.
        let past = await limiter.requestSlot(now: t0.addingTimeInterval(31))
        XCTAssertEqual(past, .allowed)
    }

    func test_userProfile_healthKitNutritionEnabled_defaultsOffAndRoundTrips() throws {
        // Default: opt-in flag is off so a fresh install never writes
        // to Apple Health silently.
        let fresh = UserProfile.fresh
        XCTAssertFalse(fresh.healthKitNutritionEnabled)

        let opted = UserProfile(
            name: "Casey",
            goals: [],
            memberSince: Date(),
            healthConnected: true,
            healthKitNutritionEnabled: true
        )
        XCTAssertTrue(opted.healthKitNutritionEnabled)

        let data = try encoder.encode(opted)
        let decoded = try decoder.decode(UserProfile.self, from: data)
        XCTAssertTrue(decoded.healthKitNutritionEnabled)

        // StoredProfile round-trip too — the SwiftData sidecar carries
        // the same flag, so the toggle survives a relaunch + CloudKit
        // pull on a second device.
        let stored = try StoredProfile.make(from: opted)
        let roundTripped = try stored.toUserProfile()
        XCTAssertTrue(roundTripped.healthKitNutritionEnabled)
    }

    func test_userProfile_legacyJSON_decodesWithEmptyFoodLibraryDefaults() throws {
        // Older builds had no customFoods / favoriteFoodIDs columns —
        // their on-disk JSON omits both keys. The decode path must
        // produce empty collections (not crash) so the food library
        // boots clean on upgrade.
        let legacyJSON = """
        {
          "name": "Legacy",
          "goals": [],
          "memberSince": "2023-11-14T22:13:20Z",
          "healthConnected": false,
          "weightHistory": [],
          "progressPhotoFilenames": [],
          "dailyConsumption": {},
          "workoutHistory": [],
          "bio": ""
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(UserProfile.self, from: legacyJSON)
        XCTAssertTrue(decoded.customFoods.isEmpty)
        XCTAssertTrue(decoded.favoriteFoodIDs.isEmpty)
        XCTAssertTrue(decoded.mealHistory.isEmpty)
        XCTAssertFalse(decoded.healthKitNutritionEnabled)
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

    func test_storedProfile_make_preservesCustomFoodsAndFavorites() throws {
        // Mirrors the `customization` round-trip but for the food-library
        // fields. The SwiftData sidecar uses `.iso8601` date encoding —
        // we pin `updatedAt` to a deterministic value so a drift between
        // the Codable path and the SwiftData path would surface as a
        // failing equality check on the round-tripped date.
        let updatedAt = Date(timeIntervalSince1970: 1_715_000_000)
        let nutrients = ScannedProduct.Nutriments(
            calories: 250,
            proteinG: 18,
            carbsG: 30,
            fatG: 6,
            fiberG: 4,
            sugarsG: 5
        )
        let custom = CustomFood(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Overnight oats",
            brand: "Meal prep",
            per100g: nutrients,
            servingGrams: 250,
            servingLabel: "1 jar",
            updatedAt: updatedAt
        )
        let profile = UserProfile(
            name: "Casey",
            goals: ["Recovery"],
            memberSince: Date(),
            healthConnected: false,
            customFoods: [custom],
            favoriteFoodIDs: ["5449000000996", custom.foodID]
        )

        let stored = try StoredProfile.make(from: profile)
        let roundTripped = try stored.toUserProfile()

        XCTAssertEqual(roundTripped.customFoods.count, 1)
        let restored = try XCTUnwrap(roundTripped.customFoods.first)
        XCTAssertEqual(restored.id, custom.id)
        XCTAssertEqual(restored.name, custom.name)
        XCTAssertEqual(restored.brand, custom.brand)
        XCTAssertEqual(restored.per100g.calories, custom.per100g.calories)
        XCTAssertEqual(restored.servingGrams, custom.servingGrams)
        XCTAssertEqual(restored.servingLabel, custom.servingLabel)
        // ISO 8601 has second precision; the pinned fixture date sits
        // on a whole second so this comparison is stable.
        XCTAssertEqual(
            restored.updatedAt.timeIntervalSince1970.rounded(),
            updatedAt.timeIntervalSince1970.rounded()
        )
        XCTAssertTrue(roundTripped.favoriteFoodIDs.contains("5449000000996"))
        XCTAssertTrue(roundTripped.favoriteFoodIDs.contains(custom.foodID))
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
