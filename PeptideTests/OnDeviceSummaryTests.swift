import XCTest
@testable import Peptide

@MainActor
final class OnDeviceSummaryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnDeviceSummaryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func coachingFacts() throws -> OnDeviceSummaryEngine.Facts {
        let message = CoachingMessageEngine.CoachingMessage(
            icon: "bed.double.fill", eyebrow: "COACHING", title: "Short sleep — 5.2 h",
            body: "Cap intensity today.", tone: .cautionary)
        let context = CoachingMessageEngine.Context(hasProtocols: true, healthConnected: true,
                                                    recoveryScore: 55, sleepHours: 5.2)
        return try XCTUnwrap(OnDeviceSummaryEngine.coaching(message, context: context, now: now))
    }

    private func service(available: Bool,
                         timeout: Duration = .seconds(5),
                         generator: @escaping OnDeviceSummaryService.Generator) -> OnDeviceSummaryService {
        OnDeviceSummaryService(defaults: defaults, modelAvailable: { available },
                               timeout: timeout, generator: generator)
    }

    // MARK: - Fact building

    func test_workoutFacts_restateEngineNumbers() throws {
        let session = WorkoutRecapFixture.push(finishedAt: now)
        let summary = WorkoutRecapEngine.derive(session, catalog: [:])
        let facts = try XCTUnwrap(OnDeviceSummaryEngine.workout(summary, newPRCount: 2, weekCount: 3,
                                                               unit: .metric, now: now))
        XCTAssertEqual(facts.kind, .workout)
        XCTAssertNil(facts.fallback)
        XCTAssertTrue(facts.statements.contains("Workout: Push Workout"))
        XCTAssertTrue(facts.statements.contains("Exercises completed: 5"))
        XCTAssertTrue(facts.statements.contains("Working sets completed: 15"))
        XCTAssertTrue(facts.statements.contains("Duration: 42 minutes"))
        XCTAssertTrue(facts.statements.contains("New personal records: 2"))
        XCTAssertTrue(facts.statements.contains("Workouts completed this week, including this one: 3"))
        let volume = try XCTUnwrap(summary.volumeKg)
        XCTAssertTrue(facts.statements.contains("Total volume lifted: \(RecapFormat.volume(volume, unit: .metric))"))
    }

    func test_workoutFacts_noPRsOrWeek_omitsThoseLines() throws {
        let summary = WorkoutRecapEngine.derive(WorkoutRecapFixture.push(finishedAt: now), catalog: [:])
        let facts = try XCTUnwrap(OnDeviceSummaryEngine.workout(summary, newPRCount: 0, weekCount: nil,
                                                               unit: .metric, now: now))
        XCTAssertFalse(facts.statements.contains { $0.hasPrefix("New personal records") })
        XCTAssertFalse(facts.statements.contains { $0.hasPrefix("Workouts completed this week") })
    }

    func test_workoutFacts_noWorkingSets_returnsNil() {
        var session = WorkoutRecapFixture.push(finishedAt: now)
        session.exercises = []
        let summary = WorkoutRecapEngine.derive(session, catalog: [:])
        XCTAssertNil(OnDeviceSummaryEngine.workout(summary, newPRCount: 0, weekCount: 1, unit: .metric, now: now))
    }

    func test_weekFacts_countsTrainedDays_andEmptyWeekIsNil() throws {
        let day = Calendar.current.startOfDay(for: now)
        let days = (0..<7).map { offset in
            WorkoutRecapEngine.Day(date: day.addingTimeInterval(Double(offset) * 86_400),
                                   count: offset == 1 ? 2 : (offset == 4 ? 1 : 0))
        }
        let week = WorkoutRecapEngine.Week(days: days, count: 3, volumeKg: nil, isCurrent: true)
        let facts = try XCTUnwrap(OnDeviceSummaryEngine.week(week, unit: .metric, now: now))
        XCTAssertEqual(facts.statements, [
            "Workouts completed so far this week: 3",
            "Days with a workout this week: 2"
        ])
        let empty = WorkoutRecapEngine.Week(days: days.map { .init(date: $0.date, count: 0) }, count: 0, volumeKg: nil,
                                             isCurrent: true)
        XCTAssertNil(OnDeviceSummaryEngine.week(empty, unit: .metric, now: now))
    }

    func test_weekFacts_pastWeek_doesNotSayThisWeek() throws {
        let day = Calendar.current.startOfDay(for: now)
        let days = (0..<7).map { WorkoutRecapEngine.Day(date: day.addingTimeInterval(Double($0) * 86_400), count: $0 == 2 ? 1 : 0) }
        let week = WorkoutRecapEngine.Week(days: days, count: 1, volumeKg: nil, isCurrent: false)
        let facts = try XCTUnwrap(OnDeviceSummaryEngine.week(week, unit: .metric, now: now))
        XCTAssertEqual(facts.statements, ["Workouts completed that week: 1", "Days with a workout that week: 1"])
    }

    func test_coachingFacts_fallbackIsDeterministicBody() throws {
        let facts = try coachingFacts()
        XCTAssertEqual(facts.fallback, "Cap intensity today.")
        XCTAssertTrue(facts.statements.contains("Recovery score today: 55%"))
        XCTAssertTrue(facts.statements.contains("Sleep last night: 5.2 hours"))
    }

    func test_coachingFacts_welcomeOrBodyless_returnsNil() {
        let context = CoachingMessageEngine.Context(hasProtocols: false, healthConnected: false)
        let welcome = CoachingMessageEngine.CoachingMessage(icon: "sparkles", eyebrow: "WELCOME",
                                                            title: "Hi", body: "Body", tone: .welcome)
        let bodyless = CoachingMessageEngine.CoachingMessage(icon: "sparkles", eyebrow: "COACHING",
                                                             title: "Hi", body: nil, tone: .neutral)
        XCTAssertNil(OnDeviceSummaryEngine.coaching(welcome, context: context, now: now))
        XCTAssertNil(OnDeviceSummaryEngine.coaching(bodyless, context: context, now: now))
    }

    func test_cacheKey_differsByDay() throws {
        let summary = WorkoutRecapEngine.derive(WorkoutRecapFixture.push(finishedAt: now), catalog: [:])
        let today = try XCTUnwrap(OnDeviceSummaryEngine.workout(summary, newPRCount: 0, weekCount: 1,
                                                               unit: .metric, now: now))
        let tomorrow = try XCTUnwrap(OnDeviceSummaryEngine.workout(summary, newPRCount: 0, weekCount: 1,
                                                                  unit: .metric, now: now.addingTimeInterval(86_400)))
        XCTAssertNotEqual(today.cacheKey, tomorrow.cacheKey)
    }

    // MARK: - Validation

    func test_numbers_normalizesGroupingAndDecimals() {
        XCTAssertEqual(OnDeviceSummaryEngine.numbers(in: "6,720 kg in 42 min, 5.2 h."), ["6720", "42", "52"])
        XCTAssertEqual(OnDeviceSummaryEngine.numbers(in: "Sets: 15, reps 10."), ["15", "10"])
        XCTAssertTrue(OnDeviceSummaryEngine.numbers(in: "No digits here").isEmpty)
    }

    func test_accept_restatedNumbers_isAccepted() throws {
        let facts = try coachingFacts()
        XCTAssertEqual(OnDeviceSummaryEngine.accept("  With 5.2 hours of sleep, keep today light.\n", for: facts),
                       "With 5.2 hours of sleep, keep today light.")
    }

    func test_accept_inventedNumber_isRejected() throws {
        let facts = try coachingFacts()
        XCTAssertNil(OnDeviceSummaryEngine.accept("Sleep 8 hours tonight and cap intensity.", for: facts))
    }

    func test_accept_emptyOrOverlong_isRejected() throws {
        let facts = try coachingFacts()
        XCTAssertNil(OnDeviceSummaryEngine.accept("   ", for: facts))
        XCTAssertNil(OnDeviceSummaryEngine.accept(String(repeating: "a", count: OnDeviceSummaryEngine.maxLength + 1),
                                                  for: facts))
    }

    func test_prompt_listsEveryFact() throws {
        let facts = try coachingFacts()
        let prompt = OnDeviceSummaryEngine.prompt(for: facts)
        for statement in facts.statements { XCTAssertTrue(prompt.contains("- \(statement)")) }
    }

    // MARK: - Service fallback paths

    func test_service_modelUnavailable_returnsFallbackWithoutGenerating() async throws {
        let facts = try coachingFacts()
        let sut = service(available: false) { _, _ in
            XCTFail("Generator must not run when the model is unavailable")
            return "unused"
        }
        await sut.prepare(facts)
        XCTAssertFalse(sut.isSupported)
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
    }

    func test_service_validOutput_upgradesFallback() async throws {
        let facts = try coachingFacts()
        let sut = service(available: true) { _, _ in "Keep today light after 5.2 hours of sleep." }
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
        await sut.prepare(facts)
        XCTAssertEqual(sut.text(for: facts), "Keep today light after 5.2 hours of sleep.")
    }

    func test_service_inventedNumber_keepsFallback() async throws {
        let facts = try coachingFacts()
        let sut = service(available: true) { _, _ in "Recovery is 90% — go hard." }
        await sut.prepare(facts)
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
    }

    func test_service_generatorThrows_keepsFallback() async throws {
        let facts = try coachingFacts()
        let sut = service(available: true) { _, _ in throw OnDeviceSummaryService.ModelUnavailable() }
        await sut.prepare(facts)
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
    }

    func test_service_slowModel_timesOutToFallback() async throws {
        let facts = try coachingFacts()
        let sut = service(available: true, timeout: .milliseconds(50)) { _, _ in
            try await Task.sleep(for: .seconds(10))
            return "Keep today light."
        }
        await sut.prepare(facts)
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
    }

    func test_service_disabled_returnsFallbackAndPersists() async throws {
        let facts = try coachingFacts()
        let sut = service(available: true) { _, _ in "Keep today light." }
        await sut.prepare(facts)
        XCTAssertEqual(sut.text(for: facts), "Keep today light.")
        sut.setEnabled(false)
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
        XCTAssertEqual(defaults.object(forKey: OnDeviceSummaryService.enabledKey) as? Bool, false)
        let reloaded = service(available: true) { _, _ in "unused" }
        XCTAssertFalse(reloaded.isEnabled)
    }

    func test_service_enabledByDefault() {
        XCTAssertTrue(service(available: true) { _, _ in "" }.isEnabled)
    }

    /// Simulator CI has no Apple Intelligence model, so the real system
    /// path must hand back the deterministic copy.
    func test_systemService_withoutModel_returnsFallback() async throws {
        try XCTSkipIf(OnDeviceSummaryService.systemModelAvailable(), "On-device model is available here")
        let facts = try coachingFacts()
        let sut = OnDeviceSummaryService(defaults: defaults)
        await sut.prepare(facts)
        XCTAssertEqual(sut.text(for: facts), "Cap intensity today.")
    }
}
