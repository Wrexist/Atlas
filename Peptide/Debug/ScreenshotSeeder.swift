import Foundation

/// One-shot seeder for App Store screenshot capture.
///
/// Implements the data state described in
/// `docs/SCREENSHOT_SEED_DATA_AND_FIXES.md` — three protocols (Joint
/// Recovery, Daily Foundations, Cognitive Routine), 35 days of dose
/// history at the curated adherence pattern (Tuesday gaps so the
/// "Tuesdays slip" insight surfaces honestly), and a 23-day current
/// streak.
///
/// Wipes the existing data store before seeding. Reachable in DEBUG and
/// TestFlight builds via the in-app control panel; unreachable in App
/// Store Release per `ScreenshotTools.isAvailable`.
@MainActor
enum ScreenshotSeeder {
    /// Seeds the full screenshot data set: protocols, history, profile,
    /// achievements, and the Pro override.
    static func seedAll(into dataStore: DataStore) {
        guard ScreenshotTools.isAvailable else { return }
        let protocols = buildProtocols()
        let historical = buildHistory(for: protocols)
        let today = buildToday(for: protocols)
        let entries = historical + today

        dataStore.replaceAllForScreenshots(
            protocols: protocols,
            entries: entries,
            profile: buildProfile()
        )

        // Re-seeding always starts the achievement state from scratch so the
        // unlock dates are anchored to the new history.
        AchievementService.shared.resetForTesting()
        AchievementService.shared.checkAchievements(
            totalDoses: entries.filter(\.completed).count,
            currentStreak: 23,
            bestStreak: 23,
            protocolCount: protocols.count,
            daysLogged: 30
        )

        ScreenshotMode.shared.setActive(true)
    }

    /// Wipes everything back to a clean install state. Useful for
    /// re-shooting a slot from a known baseline.
    static func wipe(_ dataStore: DataStore) {
        guard ScreenshotTools.isAvailable else { return }
        dataStore.replaceAllForScreenshots(
            protocols: [],
            entries: [],
            profile: .fresh
        )
        AchievementService.shared.resetForTesting()
        ScreenshotMode.shared.setActive(false)
    }

    // MARK: - Protocols

    private static func buildProtocols() -> [PeptideProtocol] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var result: [PeptideProtocol] = []

        // Protocol A — "Joint Recovery 8-Week" (week 5 of 8 → started 4 weeks ago).
        if let bpc = peptide(abbr: "BPC-157"), let tb500 = peptide(abbr: "TB-500") {
            let bpcSchedule = ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: 2,
                preferredTimes: ["8:00 AM", "8:00 PM"],
                customDose: "250 mcg"
            )
            let tbSchedule = ProtocolSchedule(
                daysOfWeek: [1, 4],
                timesPerDay: 1,
                preferredTimes: ["9:00 AM"],
                customDose: "2 mg"
            )
            let proto = PeptideProtocol(
                id: UUID(),
                name: "Joint Recovery 8-Week",
                peptides: [bpc, tb500],
                schedule: bpcSchedule,
                peptideSchedules: [tb500.id: tbSchedule],
                cycleLengthWeeks: 8,
                startDate: calendar.date(byAdding: .day, value: -28, to: today) ?? today,
                status: .active,
                notes: "Post-meniscus rehab. Pair with PT 3x/week."
            )
            result.append(proto)
        }

        // Protocol B — "Daily Foundations" (day 87 → started ~12 weeks ago).
        // Glycine isn't in the peptide DB, so we substitute Thymosin Alpha-1
        // for the third slot — keeps the multi-route, multi-frequency story
        // the screenshot relies on.
        if let glutathione = peptide(abbr: "GSH"),
           let nad = peptide(abbr: "NAD+"),
           let ta1 = peptide(abbr: "TA1") {
            let glutSchedule = ProtocolSchedule(
                daysOfWeek: [1, 3, 5],
                timesPerDay: 1,
                preferredTimes: ["7:00 AM"],
                customDose: "200 mg"
            )
            let nadSchedule = ProtocolSchedule(
                daysOfWeek: [7],
                timesPerDay: 1,
                preferredTimes: ["10:00 AM"],
                customDose: "100 mg"
            )
            let ta1Schedule = ProtocolSchedule(
                daysOfWeek: [1, 4],
                timesPerDay: 1,
                preferredTimes: ["7:30 AM"],
                customDose: "1.6 mg"
            )
            let proto = PeptideProtocol(
                id: UUID(),
                name: "Daily Foundations",
                peptides: [glutathione, nad, ta1],
                schedule: glutSchedule,
                peptideSchedules: [
                    nad.id: nadSchedule,
                    ta1.id: ta1Schedule,
                ],
                cycleLengthWeeks: 26,
                startDate: calendar.date(byAdding: .day, value: -87, to: today) ?? today,
                status: .active,
                notes: "Baseline routine. No cycling."
            )
            result.append(proto)
        }

        // Protocol C — "Cognitive Routine 5/2" (week 3 → started ~14 days ago).
        if let selank = peptide(abbr: "Selank"), let semax = peptide(abbr: "Semax") {
            let schedule = ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5],
                timesPerDay: 1,
                preferredTimes: ["8:30 AM"],
                customDose: "500 mcg"
            )
            let semaxSchedule = ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5],
                timesPerDay: 1,
                preferredTimes: ["8:45 AM"],
                customDose: "600 mcg"
            )
            let proto = PeptideProtocol(
                id: UUID(),
                name: "Cognitive Routine 5/2",
                peptides: [selank, semax],
                schedule: schedule,
                peptideSchedules: [semax.id: semaxSchedule],
                cycleLengthWeeks: 6,
                startDate: calendar.date(byAdding: .day, value: -14, to: today) ?? today,
                status: .active,
                notes: "Workdays only. Off on weekends."
            )
            result.append(proto)
        }

        return result
    }

    // MARK: - History

    /// Builds 35 days of dose log history shaped to the §2 adherence curve:
    ///
    /// ```
    /// Week -5: 60% — protocol just started
    /// Week -4: 72% — Tuesday fully missed (travel)
    /// Week -3: 78% — Tuesday partial
    /// Week -2: 70% — Tuesday partial, Sunday missed
    /// Week -1: 85%
    /// Week  0: 95% — building current 23-day streak
    /// ```
    ///
    /// The Tuesday gaps are the data shape that lets the InsightEngine's
    /// day-of-week analyzer surface "You tend to miss doses on Tuesdays."
    private static func buildHistory(for protocols: [PeptideProtocol]) -> [ProtocolEntry] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        var entries: [ProtocolEntry] = []

        // Day offsets: -34 (oldest) through -1 (yesterday). 35 days total.
        for dayOffset in (1...34).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }
            let weekIndex = (dayOffset - 1) / 7  // 0 = most recent week, 4 = oldest
            let weekday = calendar.component(.weekday, from: date)  // 1=Sun…7=Sat
            let isTuesday = weekday == 3
            let isSunday = weekday == 1

            for proto in protocols {
                guard let scheduleDay = scheduledEntries(for: proto, on: date) else { continue }
                for slot in scheduleDay {
                    let completed = shouldCompleteEntry(
                        weekIndex: weekIndex,
                        isTuesday: isTuesday,
                        isSunday: isSunday,
                        timeIndex: slot.timeIndex,
                        dayOffset: dayOffset
                    )
                    let actualTime: Date? = completed
                        ? slot.scheduledDate.addingTimeInterval(Double.random(in: -300...600))
                        : nil
                    let note = completed ? "" : Self.skipNote(weekIndex: weekIndex, isTuesday: isTuesday)
                    let entry = ProtocolEntry(
                        id: UUID(),
                        protocolId: proto.id,
                        peptide: slot.peptide,
                        date: slot.scheduledDate,
                        dose: slot.dose,
                        notes: note,
                        completed: completed,
                        actualDose: completed ? slot.dose : nil,
                        actualTime: actualTime,
                        injectionSite: completed ? siteFor(slot.peptide) : nil
                    )
                    entries.append(entry)
                }
            }
        }

        return entries
    }

    /// Builds today's entries with most slots already logged so the Today
    /// view (slot 1) shows a 70% compliance ring with a "Next dose in 1h"
    /// card visible.
    private static func buildToday(for protocols: [PeptideProtocol]) -> [ProtocolEntry] {
        let calendar = Calendar.current
        let today = Date()
        var entries: [ProtocolEntry] = []

        for proto in protocols {
            guard let scheduledSlots = scheduledEntries(for: proto, on: today) else { continue }
            for slot in scheduledSlots {
                let isPastDue = slot.scheduledDate < today
                let entry = ProtocolEntry(
                    id: UUID(),
                    protocolId: proto.id,
                    peptide: slot.peptide,
                    date: slot.scheduledDate,
                    dose: slot.dose,
                    notes: "",
                    completed: isPastDue,
                    actualDose: isPastDue ? slot.dose : nil,
                    actualTime: isPastDue ? slot.scheduledDate : nil,
                    injectionSite: isPastDue ? siteFor(slot.peptide) : nil
                )
                entries.append(entry)
            }
        }

        return entries
    }

    // MARK: - Profile

    private static func buildProfile() -> UserProfile {
        UserProfile(
            name: "Alex",
            goals: ["Joint Health", "Better Sleep", "Anti-Aging"],
            memberSince: Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? Date(),
            healthConnected: true,
            hapticFeedbackEnabled: true,
            doseRemindersEnabled: true,
            biometricLockEnabled: false,
            bodyMetrics: BodyMetrics(
                weightKg: 78,
                heightCm: 180,
                age: 34,
                sex: .male,
                activityLevel: .active,
                unit: .imperial
            )
        )
    }

    // MARK: - Helpers

    private static func peptide(abbr: String) -> Peptide? {
        PeptideDatabase.shared.first { $0.abbreviation == abbr }
    }

    /// Per-day, per-time-slot scheduled entries for a protocol — mirrors the
    /// production scheduler logic but generalised over an arbitrary date.
    private static func scheduledEntries(for proto: PeptideProtocol, on date: Date) -> [ScheduledSlot]? {
        let calendar = Calendar.current
        guard date >= proto.startDate else { return nil }

        let weekday = calendar.component(.weekday, from: date)
        let isoDayOfWeek = weekday == 1 ? 7 : weekday - 1

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var slots: [ScheduledSlot] = []
        for peptide in proto.peptides {
            let schedule = proto.schedule(for: peptide.id)
            guard schedule.daysOfWeek.contains(isoDayOfWeek) else { continue }
            for (index, timeString) in schedule.preferredTimes.enumerated() {
                guard let time = formatter.date(from: timeString) else { continue }
                let hour = calendar.component(.hour, from: time)
                let minute = calendar.component(.minute, from: time)
                guard let scheduledDate = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: date
                ) else { continue }
                slots.append(ScheduledSlot(
                    peptide: peptide,
                    scheduledDate: scheduledDate,
                    timeIndex: index,
                    dose: schedule.resolvedDose(for: peptide)
                ))
            }
        }
        return slots.isEmpty ? nil : slots
    }

    /// Adherence shape: better recently than at the start, with Tuesday
    /// drift across the older weeks and one travel-day total skip.
    private static func shouldCompleteEntry(
        weekIndex: Int,
        isTuesday: Bool,
        isSunday: Bool,
        timeIndex: Int,
        dayOffset: Int
    ) -> Bool {
        // Travel day total skip — a single midday in week -4.
        if dayOffset == 25 { return false }

        switch weekIndex {
        case 0:  // most recent 7 days → 95%
            return Double.random(in: 0...1) < 0.95
        case 1:  // 85%
            return Double.random(in: 0...1) < 0.85
        case 2:  // 70%, with Tuesdays + one Sunday slipping
            if isTuesday { return timeIndex == 0 }
            if isSunday && dayOffset == 18 { return false }
            return Double.random(in: 0...1) < 0.78
        case 3:  // 78%, Tuesday partial
            if isTuesday { return timeIndex == 0 }
            return Double.random(in: 0...1) < 0.82
        case 4:  // 72%, Tuesday fully missed (travel)
            if isTuesday { return false }
            return Double.random(in: 0...1) < 0.78
        default:  // 60% week -5
            return Double.random(in: 0...1) < 0.60
        }
    }

    private static func skipNote(weekIndex: Int, isTuesday: Bool) -> String {
        if isTuesday {
            return weekIndex == 4 ? "Travel day, no fridge access" : "Late by 2h — meeting overran"
        }
        let pool = [
            "Forgot — woke up late",
            "Skipped intentionally — sick",
            "Rest day, off-cycle",
        ]
        return pool.randomElement() ?? ""
    }

    private static func siteFor(_ peptide: Peptide) -> String {
        let route = peptide.adminRoute.lowercased()
        if route.contains("oral") || route.contains("nasal") { return "" }
        if route.contains("intramuscular") {
            return ["Left Deltoid", "Right Deltoid"].randomElement() ?? "Left Deltoid"
        }
        return ["Left Abdomen", "Right Abdomen"].randomElement() ?? "Left Abdomen"
    }

    private struct ScheduledSlot {
        let peptide: Peptide
        let scheduledDate: Date
        let timeIndex: Int
        let dose: String
    }
}
