import SwiftUI

@MainActor @Observable
final class DataStore: DataServiceProtocol {
    var protocols: [PeptideProtocol]
    var entries: [ProtocolEntry]
    var profile: UserProfile

    private let persistence = PersistenceService.shared

    private var _peptideDatabase: [Peptide]?

    init() {
        // Load each file independently -- don't lose all data if one file is corrupt
        self.protocols = persistence.loadProtocols() ?? MockProtocols.all
        self.entries = persistence.loadEntries() ?? Self.generateInitialEntries(for: protocols)
        self.profile = persistence.loadProfile() ?? MockProfile.current
        regenerateTodayEntries()
        if !persistence.hasPersistedData { save() }
    }

    // MARK: - Peptide Database

    var peptideDatabase: [Peptide] {
        if let cached = _peptideDatabase { return cached }
        let bundled = persistence.loadPeptideDatabase()
        let result = bundled.isEmpty ? MockPeptides.all : bundled
        _peptideDatabase = result
        return result
    }

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
        protocols.insert(newProtocol, at: 0)
        appendTodayEntries(for: newProtocol)
        save()
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
    }

    func deleteProtocol(id: UUID) {
        protocols.removeAll { $0.id == id }
        entries.removeAll { $0.protocolId == id }
        save()
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
    }

    func updateProtocolStatus(id: UUID, to status: ProtocolStatus) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        protocols[index].status = status
        save()
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
    }

    // MARK: - Entries

    var todayEntries: [ProtocolEntry] {
        let calendar = Calendar.current
        let activeIds = Set(activeProtocols.map(\.id))
        return entries
            .filter { calendar.isDateInToday($0.date) && activeIds.contains($0.protocolId) }
            .sorted { $0.date < $1.date }
    }

    func toggleEntry(_ entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[index].completed.toggle()
        save()
    }

    func logDose(entryId: UUID, actualDose: String?, actualTime: Date?, injectionSite: String?, notes: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
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
        NotificationService.shared.scheduleNotifications(for: activeProtocols)
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
        let calendar = Calendar.current
        var streak = 0
        var consecutiveEmptyDays = 0

        let todayHasCompleted = todayEntries.contains(where: \.completed)
        let startOffset = todayHasCompleted ? 0 : 1

        for dayOffset in startOffset..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }

            if dayEntries.isEmpty {
                consecutiveEmptyDays += 1
                // Allow up to 2 consecutive empty days (weekends) before breaking
                if consecutiveEmptyDays > 2 { break }
                continue
            }

            consecutiveEmptyDays = 0
            if !dayEntries.contains(where: \.completed) { break }
            streak += 1
        }

        return streak
    }

    var totalDaysLogged: Int {
        let calendar = Calendar.current
        let days = Set(entries.filter(\.completed).map { calendar.startOfDay(for: $0.date) })
        return days.count
    }

    var totalDoses: Int {
        entries.filter(\.completed).count
    }

    var bestStreak: Int {
        let calendar = Calendar.current

        // Get all days that had entries (scheduled days only)
        let scheduledDays = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !scheduledDays.isEmpty else { return 0 }

        // For each scheduled day, check if it had at least one completed entry
        let completedDaySet = Set(entries.filter(\.completed).map { calendar.startOfDay(for: $0.date) })

        var best = 0
        var current = 0

        for day in scheduledDays {
            if completedDaySet.contains(day) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }

        return best
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
        let now = Date()
        let today = todayEntries
        return today.first { !$0.completed && $0.date > now }
            ?? today.first { !$0.completed }
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

    // MARK: - Persistence

    private var achievementCheckPending = false

    private func save() {
        persistence.saveProtocols(protocols)
        persistence.saveEntries(entries)
        persistence.saveProfile(profile)
        scheduleAchievementCheck()
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
            // Historical entries, excluding today to avoid duplicates with timed entries
            let historical = MockEntries.generateEntries(for: proto, days: 30)
                .filter { !calendar.isDateInToday($0.date) }
            allEntries.append(contentsOf: historical)

            // Today's entries with proper times from schedule
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
        let newEntries = Self.generateTodayEntries(for: proto)
        entries.append(contentsOf: newEntries)
    }
}
