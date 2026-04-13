import SwiftUI
import WidgetKit

@MainActor @Observable
final class DataStore: DataServiceProtocol {
    var protocols: [PeptideProtocol]
    var entries: [ProtocolEntry]
    var profile: UserProfile

    private let persistence = PersistenceService.shared
    private let _peptideDatabase: [Peptide] = PeptideDatabase.shared

    // MARK: - Cache (avoids recomputing expensive stats on every toggle)
    @ObservationIgnored private var _cachedTodayEntries: [ProtocolEntry]?
    @ObservationIgnored private var _cachedCurrentStreak: Int?
    @ObservationIgnored private var _cachedTotalDaysLogged: Int?
    @ObservationIgnored private var _cachedBestStreak: Int?
    @ObservationIgnored private var _cachedNextDose: ProtocolEntry??
    @ObservationIgnored private var _cachedWeeklyCompletion: [WeekDayStatus]?
    @ObservationIgnored private var _entriesByDay: [Date: [ProtocolEntry]]?
    @ObservationIgnored private var _cacheDate: Date?

    private func invalidateCache() {
        _cachedTodayEntries = nil
        _cachedCurrentStreak = nil
        _cachedTotalDaysLogged = nil
        _cachedBestStreak = nil
        _cachedNextDose = nil
        _cachedWeeklyCompletion = nil
        _entriesByDay = nil
        _cacheDate = nil
    }

    private func invalidateCacheIfDayChanged() {
        guard let cacheDate = _cacheDate else {
            _cacheDate = Date()
            return
        }
        if !Calendar.current.isDateInToday(cacheDate) {
            invalidateCache()
            _cacheDate = Date()
        }
    }

    private var entriesByDay: [Date: [ProtocolEntry]] {
        if let cached = _entriesByDay { return cached }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        _entriesByDay = grouped
        return grouped
    }

    init(seedSampleData: Bool = false) {
        let savedProtocols = persistence.loadProtocols()
        let savedEntries = persistence.loadEntries()
        let savedProfile = persistence.loadProfile()

        if savedProtocols != nil || savedEntries != nil || savedProfile != nil {
            // Returning user: recover what we can. Using || (not &&) so a single
            // corrupt file doesn't erase the user's entire dataset.
            self.protocols = savedProtocols ?? []
            self.entries = savedEntries ?? []
            self.profile = savedProfile ?? .fresh
            regenerateTodayEntries()
        } else if seedSampleData {
            // Tests/previews: seed mock data
            let sampleProtocols = MockProtocols.all
            self.protocols = sampleProtocols
            self.entries = Self.generateInitialEntries(for: sampleProtocols)
            self.profile = MockProfile.current
            regenerateTodayEntries()
            save()
        } else {
            // First launch: clean slate, no entries to generate
            self.protocols = []
            self.entries = []
            self.profile = .fresh
        }
    }

    // MARK: - Peptide Database

    var peptideDatabase: [Peptide] { _peptideDatabase }

    // MARK: - Protocols

    var activeProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .active }
    }

    var pausedProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .paused }
    }

    var completedProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .completed }
    }

    func addProtocol(_ newProtocol: PeptideProtocol) {
        invalidateCache()
        protocols.insert(newProtocol, at: 0)
        appendTodayEntries(for: newProtocol)
        save()
        rescheduleNotificationsIfEnabled()
        if profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func deleteProtocol(id: UUID) {
        invalidateCache()
        protocols.removeAll { $0.id == id }
        entries.removeAll { $0.protocolId == id }
        save()
        rescheduleNotificationsIfEnabled()
    }

    func updateProtocolStatus(id: UUID, to status: ProtocolStatus) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        invalidateCache()
        protocols[index].status = status
        if status == .active {
            appendTodayEntries(for: protocols[index])
        }
        save()
        rescheduleNotificationsIfEnabled()
    }

    // MARK: - Entries

    var todayEntries: [ProtocolEntry] {
        invalidateCacheIfDayChanged()
        if let cached = _cachedTodayEntries { return cached }
        let calendar = Calendar.current
        let activeIds = Set(activeProtocols.map(\.id))
        let result = entries
            .filter { calendar.isDateInToday($0.date) && activeIds.contains($0.protocolId) }
            .sorted { $0.date < $1.date }
        _cachedTodayEntries = result
        return result
    }

    func toggleEntry(_ entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let becoming = !entries[index].completed
        invalidateCache()
        entries[index].completed.toggle()
        save()
        if profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: becoming ? .light : .soft).impactOccurred()
        }
    }

    func logDose(entryId: UUID, actualDose: String?, actualTime: Date?, injectionSite: String?, notes: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        invalidateCache()
        let existing = entries[index]
        entries[index] = ProtocolEntry(
            id: existing.id,
            protocolId: existing.protocolId,
            peptide: existing.peptide,
            date: existing.date,
            dose: existing.dose,
            notes: notes.isEmpty ? existing.notes : notes,
            completed: true,
            actualDose: actualDose,
            actualTime: actualTime,
            injectionSite: injectionSite
        )
        save()
    }

    func updateProtocol(id: UUID, name: String, peptides: [Peptide], schedule: ProtocolSchedule, cycleLengthWeeks: Int, notes: String) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        invalidateCache()
        let updated = PeptideProtocol(
            id: id,
            name: name,
            peptides: peptides,
            schedule: schedule,
            cycleLengthWeeks: cycleLengthWeeks,
            startDate: protocols[index].startDate,
            status: protocols[index].status,
            notes: notes
        )
        protocols[index] = updated
        save()
        rescheduleNotificationsIfEnabled()
    }

    func entriesFor(protocolId: UUID, days: Int = 14) -> [ProtocolEntry] {
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        )
        return entries
            .filter { $0.protocolId == protocolId && $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Computed Stats

    var currentStreak: Int {
        if let cached = _cachedCurrentStreak { return cached }
        let calendar = Calendar.current
        let grouped = entriesByDay
        let todayStart = calendar.startOfDay(for: Date())

        let todayHasCompleted = todayEntries.contains(where: \.completed)
        let startOffset = todayHasCompleted ? 0 : 1

        var streak = 0
        var consecutiveEmptyDays = 0
        for dayOffset in startOffset..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { break }
            let dayEntries = grouped[date] ?? []

            if dayEntries.isEmpty {
                consecutiveEmptyDays += 1
                if consecutiveEmptyDays > 2 { break }
                continue
            }

            consecutiveEmptyDays = 0
            if !dayEntries.contains(where: \.completed) { break }
            streak += 1
        }

        _cachedCurrentStreak = streak
        return streak
    }

    var totalDaysLogged: Int {
        if let cached = _cachedTotalDaysLogged { return cached }
        let result = entriesByDay.values.filter { dayEntries in
            dayEntries.contains(where: \.completed)
        }.count
        _cachedTotalDaysLogged = result
        return result
    }

    var totalDoses: Int {
        entries.filter(\.completed).count
    }

    var bestStreak: Int {
        if let cached = _cachedBestStreak { return cached }
        let grouped = entriesByDay
        let scheduledDays = grouped.keys.sorted()
        guard !scheduledDays.isEmpty else { return 0 }

        var best = 0
        var current = 0

        for day in scheduledDays {
            if let dayEntries = grouped[day], dayEntries.contains(where: \.completed) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }

        _cachedBestStreak = best
        return best
    }

    var weeklyCompletion: [WeekDayStatus] {
        invalidateCacheIfDayChanged()
        if let cached = _cachedWeeklyCompletion { return cached }
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)

        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = weekday == 1 ? -6 : -(weekday - 2)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: todayStart) else { return [] }

        let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
        let grouped = entriesByDay

        let result = (0..<7).map { offset -> WeekDayStatus in
            let dayDate = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let dayStart = calendar.startOfDay(for: dayDate)
            let isToday = dayStart == todayStart
            let isFuture = dayStart > todayStart

            let dayEntries = grouped[dayStart] ?? []

            let status: DayCompletionStatus
            if isFuture {
                status = .future
            } else if dayEntries.isEmpty {
                status = .noSchedule
            } else if isToday {
                let allDone = dayEntries.allSatisfy(\.completed)
                status = allDone ? .completed : .today
            } else {
                let completedCount = dayEntries.filter(\.completed).count
                if completedCount == dayEntries.count {
                    status = .completed
                } else if completedCount > 0 {
                    status = .partial
                } else {
                    status = .missed
                }
            }

            return WeekDayStatus(id: offset + 1, dayLabel: dayLabels[offset], status: status)
        }

        _cachedWeeklyCompletion = result
        return result
    }

    var averageCompliance: Double {
        let calendar = Calendar.current
        let now = Date()
        let pastEntries = entries.filter { $0.date <= now }
        let grouped = Dictionary(grouping: pastEntries) { calendar.startOfDay(for: $0.date) }
        guard !grouped.isEmpty else { return 0 }

        let dailyCompliance = grouped.map { _, dayEntries in
            let completed = dayEntries.filter(\.completed).count
            return Double(completed) / Double(dayEntries.count)
        }

        return dailyCompliance.reduce(0, +) / Double(dailyCompliance.count)
    }

    func complianceTrend(for range: Int) -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard range > 1 else { return 0 }

        let halfPoint = range / 2
        guard let midCutoff = calendar.date(byAdding: .day, value: -halfPoint, to: now),
              let startCutoff = calendar.date(byAdding: .day, value: -range, to: now) else { return 0 }

        let recentEntries = entries.filter { $0.date >= midCutoff && $0.date <= now }
        let olderEntries = entries.filter { $0.date >= startCutoff && $0.date < midCutoff }

        let recentRate = recentEntries.isEmpty ? 0 : Double(recentEntries.filter(\.completed).count) / Double(recentEntries.count)
        let olderRate = olderEntries.isEmpty ? 0 : Double(olderEntries.filter(\.completed).count) / Double(olderEntries.count)

        return recentRate - olderRate
    }

    // MARK: - Next Dose

    var nextDose: ProtocolEntry? {
        invalidateCacheIfDayChanged()
        if let cached = _cachedNextDose { return cached }
        let now = Date()
        let today = todayEntries
        let result = today.first { !$0.completed && $0.date > now }
            ?? today.first { !$0.completed }
        _cachedNextDose = .some(result)
        return result
    }

    // MARK: - Profile

    func updateGoals(_ goals: Set<String>) {
        profile.goals = Array(goals).sorted()
        save()
    }

    func toggleHealthConnection() {
        profile.healthConnected.toggle()
        save()
    }

    /// Persists the current profile state. Call after direct property mutations
    /// via bindings (e.g. settings toggles) that bypass dedicated update methods.
    func persistProfile() {
        save()
    }

    // MARK: - Notifications

    private func rescheduleNotificationsIfEnabled() {
        guard profile.doseRemindersEnabled else { return }
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
    }

    // MARK: - Persistence

    private var achievementCheckPending = false

    private func save() {
        persistence.saveProtocols(protocols)
        persistence.saveEntries(entries)
        persistence.saveProfile(profile)
        updateWidgetData()
        scheduleAchievementCheck()
    }

    private func updateWidgetData() {
        let today = todayEntries
        let completed = today.filter(\.completed).count
        let next = nextDose

        let data = WidgetData(
            nextPeptideName: next?.peptide.abbreviation ?? "",
            nextDose: next?.dose ?? "",
            nextDoseTime: next?.date,
            completedToday: completed,
            totalToday: today.count,
            lastUpdated: Date()
        )

        persistence.updateWidgetData(data)
        Task { WidgetCenter.shared.reloadAllTimelines() }
    }

    private func scheduleAchievementCheck() {
        guard !achievementCheckPending else { return }
        achievementCheckPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.achievementCheckPending = false
            AchievementService.shared.checkAchievements(
                totalDoses: self.totalDoses,
                currentStreak: self.currentStreak,
                bestStreak: self.bestStreak,
                protocolCount: self.protocols.count,
                daysLogged: self.totalDaysLogged
            )
        }
    }

    private func regenerateTodayEntries() {
        let calendar = Calendar.current
        let existingProtocolIds = Set(
            entries.filter { calendar.isDateInToday($0.date) }.map(\.protocolId)
        )
        var added = false
        for proto in activeProtocols where !existingProtocolIds.contains(proto.id) {
            entries.append(contentsOf: Self.generateTodayEntries(for: proto))
            added = true
        }
        if added { save() }
    }

    // MARK: - Entry Generation

    private static func generateInitialEntries(for protocols: [PeptideProtocol]) -> [ProtocolEntry] {
        let calendar = Calendar.current
        var allEntries: [ProtocolEntry] = []

        for proto in protocols {
            let historical = MockEntries.generateEntries(for: proto, days: 30)
                .filter { !calendar.isDateInToday($0.date) }
            allEntries.append(contentsOf: historical)
            allEntries.append(contentsOf: generateTodayEntries(for: proto))
        }

        return allEntries
    }

    private static func generateTodayEntries(for proto: PeptideProtocol) -> [ProtocolEntry] {
        guard proto.status == .active else { return [] }

        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: Date())
        let isoDayOfWeek = dayOfWeek == 1 ? 7 : dayOfWeek - 1

        guard proto.schedule.daysOfWeek.contains(isoDayOfWeek) else { return [] }

        var entries: [ProtocolEntry] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for peptide in proto.peptides {
            for timeString in proto.schedule.preferredTimes {
                if let time = formatter.date(from: timeString) {
                    let hour = calendar.component(.hour, from: time)
                    let minute = calendar.component(.minute, from: time)
                    let entryDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()

                    let entry = ProtocolEntry(
                        id: UUID(),
                        protocolId: proto.id,
                        peptide: peptide,
                        date: entryDate,
                        dose: peptide.dosageRange.components(separatedBy: "-").last?.trimmingCharacters(in: .whitespaces) ?? peptide.dosageRange,
                        notes: "",
                        completed: false
                    )
                    entries.append(entry)
                }
            }
        }

        return entries
    }

    private func appendTodayEntries(for proto: PeptideProtocol) {
        let calendar = Calendar.current
        let alreadyHasToday = entries.contains {
            $0.protocolId == proto.id && calendar.isDateInToday($0.date)
        }
        guard !alreadyHasToday else { return }
        let newEntries = Self.generateTodayEntries(for: proto)
        entries.append(contentsOf: newEntries)
    }
}
