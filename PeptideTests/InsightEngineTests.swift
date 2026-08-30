import XCTest
@testable import Peptide

final class InsightEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Entries and the protocol they belong to must share an ID: streak
    /// math counts only entries whose protocol is still active, so an
    /// orphaned entry contributes nothing.
    private static let protocolID = UUID()

    private func makeEntry(daysAgo: Double, completed: Bool, weekday: Int? = nil) -> ProtocolEntry {
        let date: Date
        if let weekday {
            let calendar = Calendar.current
            var components = DateComponents()
            components.weekday = weekday == 7 ? 1 : weekday + 1
            components.hour = 10
            date = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .previousTimePreservingSmallerComponents, direction: .backward) ?? Date()
        } else {
            date = Date().addingTimeInterval(-daysAgo * 86400)
        }
        return ProtocolEntry(
            id: UUID(),
            protocolId: Self.protocolID,
            peptide: MockPeptides.bpc157,
            date: date,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    private func makeProtocol(status: ProtocolStatus = .active) -> PeptideProtocol {
        PeptideProtocol(
            id: Self.protocolID,
            name: "Test",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Date().addingTimeInterval(-30 * 86400),
            status: status,
            notes: ""
        )
    }

    // MARK: - calculateStreak

    func test_calculateStreak_emptyEntries_returnsZero() {
        let insights = InsightEngine.generateInsights(from: [], protocols: [])
        XCTAssertFalse(insights.contains { $0.title.contains("streak") || $0.title.contains("Streak") || $0.title.contains("consistency") })
    }

    func test_generateInsights_sevenDayStreak_returnsStrongStreak() {
        var entries: [ProtocolEntry] = []
        for i in 0..<7 {
            entries.append(makeEntry(daysAgo: Double(i), completed: true))
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [makeProtocol()])
        XCTAssertTrue(insights.contains { $0.title == "Strong streak!" })
    }

    func test_generateInsights_thirtyDayStreak_returnsIncredibleConsistency() {
        var entries: [ProtocolEntry] = []
        for i in 0..<30 {
            entries.append(makeEntry(daysAgo: Double(i), completed: true))
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [makeProtocol()])
        XCTAssertTrue(insights.contains { $0.title == "Incredible consistency!" })
    }

    func test_generateInsights_sixDayStreak_noStreakInsight() {
        var entries: [ProtocolEntry] = []
        for i in 0..<6 {
            entries.append(makeEntry(daysAgo: Double(i), completed: true))
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [makeProtocol()])
        XCTAssertFalse(insights.contains { $0.title == "Strong streak!" || $0.title == "Incredible consistency!" })
    }

    // MARK: - Evening miss rate

    func test_generateInsights_highEveningMissRate_returnsEveningWarning() {
        var entries: [ProtocolEntry] = []
        for i in 0..<10 {
            let date = Date().addingTimeInterval(-(Double(i) * 86400 + 3600))
            let hour = 19
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            var dc = components
            dc.hour = hour
            dc.minute = 0
            let eveningDate = Calendar.current.date(from: dc) ?? date
            entries.append(ProtocolEntry(
                id: UUID(), protocolId: UUID(), peptide: MockPeptides.bpc157,
                date: eveningDate, dose: "250mcg", notes: "", completed: i >= 4
            ))
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [makeProtocol()])
        XCTAssertTrue(insights.contains { $0.title == "Evening doses need attention" })
    }

    // MARK: - Protocol count warning

    func test_generateInsights_threeActiveProtocols_returnsManyProtocolsWarning() {
        let protocols = [makeProtocol(), makeProtocol(), makeProtocol()]
        let insights = InsightEngine.generateInsights(from: [], protocols: protocols)
        XCTAssertTrue(insights.contains { $0.title == "Many active protocols" })
    }

    func test_generateInsights_twoActiveProtocols_noProtocolWarning() {
        let protocols = [makeProtocol(), makeProtocol()]
        let insights = InsightEngine.generateInsights(from: [], protocols: protocols)
        XCTAssertFalse(insights.contains { $0.title == "Many active protocols" })
    }

    func test_generateInsights_threeProtocolsOneInactive_noProtocolWarning() {
        let protocols = [makeProtocol(status: .active), makeProtocol(status: .active), makeProtocol(status: .completed)]
        let insights = InsightEngine.generateInsights(from: [], protocols: protocols)
        XCTAssertFalse(insights.contains { $0.title == "Many active protocols" })
    }

    // MARK: - Dose milestones

    func test_generateInsights_exactlyFiftyDoses_returnsMilestoneInsight() {
        let entries = (0..<50).map { _ in makeEntry(daysAgo: 1, completed: true) }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [])
        XCTAssertTrue(insights.contains { $0.title == "Milestone reached!" && $0.description.contains("50") })
    }

    func test_generateInsights_exactlyOneHundredDoses_returnsMilestoneInsight() {
        let entries = (0..<100).map { _ in makeEntry(daysAgo: 1, completed: true) }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [])
        XCTAssertTrue(insights.contains { $0.title == "Milestone reached!" && $0.description.contains("100") })
    }

    func test_generateInsights_onlyCountsCompletedForMilestone() {
        var entries = (0..<49).map { _ in makeEntry(daysAgo: 1, completed: true) }
        entries.append(makeEntry(daysAgo: 1, completed: false))
        let insights = InsightEngine.generateInsights(from: entries, protocols: [])
        XCTAssertFalse(insights.contains { $0.title == "Milestone reached!" })
    }

    // MARK: - Compliance trend

    func test_generateInsights_improvingCompliance_returnsPositiveInsight() {
        var entries: [ProtocolEntry] = []
        // Last 7 days: all completed (100%)
        for i in 0..<7 {
            entries.append(makeEntry(daysAgo: Double(i), completed: true))
        }
        // Days 8–30: mostly missed (20%)
        for i in 8..<30 {
            entries.append(makeEntry(daysAgo: Double(i), completed: i % 5 == 0))
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [])
        XCTAssertTrue(insights.contains { $0.title == "Compliance improving" })
    }

    func test_generateInsights_decliningCompliance_returnsWarningInsight() {
        var entries: [ProtocolEntry] = []
        // Last 7 days: all missed (0%)
        for i in 0..<7 {
            entries.append(makeEntry(daysAgo: Double(i), completed: false))
        }
        // Days 8–30: all completed (100%)
        for i in 8..<30 {
            entries.append(makeEntry(daysAgo: Double(i), completed: true))
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [])
        XCTAssertTrue(insights.contains { $0.title == "Compliance dipping" })
    }

    // MARK: - Empty / no crash

    func test_generateInsights_emptyEverything_returnsEmpty() {
        let insights = InsightEngine.generateInsights(from: [], protocols: [])
        XCTAssertTrue(insights.isEmpty)
    }

    // MARK: - Day-of-week pattern

    /// When more than 30% of entries on a specific weekday are missed, the
    /// engine should surface the "Pattern detected" insight naming that day.
    func test_generateInsights_consistentMissOnSpecificWeekday_returnsPatternInsight() {
        var entries: [ProtocolEntry] = []
        // 10 Wednesday entries, 7 missed (70% miss rate)
        for i in 0..<10 {
            entries.append(makeEntry(daysAgo: Double(i * 7), completed: i < 3, weekday: 3))
        }
        // Other days are clean (full compliance) so Wednesday is the clear outlier
        for weekday in [1, 2, 4, 5] {
            for i in 0..<5 {
                entries.append(makeEntry(daysAgo: Double(i * 7), completed: true, weekday: weekday))
            }
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [makeProtocol()])
        XCTAssertTrue(insights.contains { $0.title == "Pattern detected" })
    }

    /// Below the 30% miss threshold, no pattern warning fires.
    func test_generateInsights_lowMissRate_noPatternInsight() {
        var entries: [ProtocolEntry] = []
        for weekday in 1...5 {
            for i in 0..<10 {
                entries.append(makeEntry(daysAgo: Double(i * 7), completed: i != 0, weekday: weekday))
            }
        }
        let insights = InsightEngine.generateInsights(from: entries, protocols: [makeProtocol()])
        XCTAssertFalse(insights.contains { $0.title == "Pattern detected" })
    }
}
