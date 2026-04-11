import SwiftUI

@Observable
final class DataStore {
    var protocols: [PeptideProtocol]
    var entries: [ProtocolEntry]
    var profile: UserProfile

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
        withAnimation(AppAnimation.springSnappy) {
            protocols.insert(newProtocol, at: 0)
            appendTodayEntries(for: newProtocol)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func deleteProtocol(id: UUID) {
        withAnimation(AppAnimation.springSnappy) {
            protocols.removeAll { $0.id == id }
            entries.removeAll { $0.protocolId == id }
        }
    }

    func updateProtocolStatus(id: UUID, to status: ProtocolStatus) {
        guard let index = protocols.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(AppAnimation.springSnappy) {
            protocols[index].status = status
        }
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
        let becoming = !entries[index].completed
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
        let calendar = Calendar.current
        var streak = 0

        // Start from yesterday if today has no completed entries yet
        let todayHasCompleted = todayEntries.contains(where: \.completed)
        let startOffset = todayHasCompleted ? 0 : 1

        for dayOffset in startOffset..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }

            // Skip days with no scheduled entries (non-protocol days)
            if dayEntries.isEmpty { continue }

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
        let upcoming = todayEntries.filter { !$0.completed && $0.date > now }
        if let next = upcoming.first { return next }
        return todayEntries.first { !$0.completed }
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
        let newEntries = Self.generateTodayEntries(for: proto)
        entries.append(contentsOf: newEntries)
    }
}
