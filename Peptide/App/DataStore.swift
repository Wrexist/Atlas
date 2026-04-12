import SwiftUI

@MainActor
@Observable
final class DataStore {
    var protocols: [PeptideProtocol]
    var entries: [ProtocolEntry]
    var profile: UserProfile

    // MARK: - Cache (avoids recomputing expensive stats on every toggle)
    @ObservationIgnored private var _cachedTodayEntries: [ProtocolEntry]?
    @ObservationIgnored private var _cachedCurrentStreak: Int?
    @ObservationIgnored private var _cachedTotalDaysLogged: Int?
    @ObservationIgnored private var _cachedBestStreak: Int?
    @ObservationIgnored private var _cachedNextDose: ProtocolEntry??
    @ObservationIgnored private var _cachedWeeklyCompletion: [WeekDayStatus]?
    @ObservationIgnored private var _entriesByDay: [Date: [ProtocolEntry]]?

    private func invalidateCache() {
        _cachedTodayEntries = nil
        _cachedCurrentStreak = nil
        _cachedTotalDaysLogged = nil
        _cachedBestStreak = nil
        _cachedNextDose = nil
        _cachedWeeklyCompletion = nil
        _entriesByDay = nil
    }

    private var entriesByDay: [Date: [ProtocolEntry]] {
        if let cached = _entriesByDay { return cached }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        _entriesByDay = grouped
        return grouped
    }

    init() {
        let initialProtocols = MockProtocols.all
        self.protocols = initialProtocols
        self.profile = MockProfile.current
        self.entries = Self.generateInitialEntries(for: initialProtocols)
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
        invalidateCache()
        withAnimation(AppAnimation.springSnappy) {
            protocols.insert(newProtocol, at: 0)
            appendTodayEntries(for: newProtocol)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func deleteProtocol(id: UUID) {
        invalidateCache()
        withAnimation(AppAnimation.springSnappy) {
            protocols.removeAll { $0.id == id }
            entries.removeAll { $0.protocolId == id }
        }
    }

    func updateProtocolStatus(id: UUID, to status: ProtocolStatus) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        invalidateCache()
        withAnimation(AppAnimation.springSnappy) {
            protocols[index].status = status
        }
    }

    // MARK: - Entries

    var todayEntries: [ProtocolEntry] {
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
        withAnimation(AppAnimation.springSnappy) {
            entries[index].completed.toggle()
        }
        UIImpactFeedbackGenerator(style: becoming ? .light : .soft).impactOccurred()
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
        for dayOffset in startOffset..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { break }
            let dayEntries = grouped[date] ?? []
            if dayEntries.isEmpty { continue }
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
        if let cached = _cachedWeeklyCompletion { return cached }
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)

        // Find Monday of the current ISO week
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

    // Double optional: nil = not cached, .some(nil) = cached with no result, .some(.some) = cached entry
    var nextDose: ProtocolEntry? {
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
        withAnimation(AppAnimation.springSnappy) {
            profile.goals = Array(goals).sorted()
        }
    }

    func toggleHealthConnection() {
        withAnimation(AppAnimation.springSnappy) {
            profile.healthConnected.toggle()
        }
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
        // Cache already invalidated by caller (addProtocol)
        let newEntries = Self.generateTodayEntries(for: proto)
        entries.append(contentsOf: newEntries)
    }
}
