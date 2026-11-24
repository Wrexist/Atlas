import Foundation
import Observation

/// The health journal, one JSON file in Documents. On-device only, like
/// progress photos: the notes are the user's private words about their
/// health and never sync.
@MainActor @Observable
final class HealthJournalStore {
    static let shared = HealthJournalStore()

    /// Newest first.
    private(set) var entries: [HealthJournalEntry] = []

    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = HealthJournalStore.defaultFileURL) {
        self.fileURL = fileURL
        entries = load()
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("health-journal.json")
    }

    /// Matched by calendar day, not by instant, so a day written in
    /// another time zone is still found.
    func entry(on date: Date, calendar: Calendar = .current) -> HealthJournalEntry? {
        let key = HealthJournalEntry.dayKey(for: date, calendar: calendar)
        return entries.first { $0.dayKey == key }
    }

    /// Sets the mood and note for `date`'s day, replacing that day's entry.
    func save(mood: HealthJournalEntry.Mood, note: String, on date: Date = .now, calendar: Calendar = .current) {
        let key = HealthJournalEntry.dayKey(for: date, calendar: calendar)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = entries.firstIndex(where: { $0.dayKey == key }) {
            entries[index].mood = mood
            entries[index].note = trimmed
        } else {
            let day = calendar.startOfDay(for: date)
            entries.append(HealthJournalEntry(day: day, mood: mood, note: trimmed, calendar: calendar))
            entries.sort { $0.day > $1.day }
        }
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// A backup's journal, merged by `DeviceLocalBackup`.
    func restore(_ restored: [HealthJournalEntry]) {
        entries = restored.sorted { $0.day > $1.day }
        persist()
    }

    /// "Delete all data" — the journal must not survive an erase.
    func deleteAll() {
        entries = []
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: - Disk

    private func load() -> [HealthJournalEntry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([HealthJournalEntry].self, from: data).sorted { $0.day > $1.day }
        } catch {
            AppLog.persistence.error("Health journal unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(entries).write(to: fileURL, options: [.atomic, .completeFileProtection])
            // `.atomic` replaces the file, and the exclusion flag lives
            // on the file, not the path.
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            AppLog.persistence.error("Health journal not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
