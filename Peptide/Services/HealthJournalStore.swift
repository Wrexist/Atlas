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

    func entry(on date: Date, calendar: Calendar = .current) -> HealthJournalEntry? {
        let day = calendar.startOfDay(for: date)
        return entries.first { $0.day == day }
    }

    /// Sets the mood and note for `date`'s day, replacing that day's entry.
    func save(mood: HealthJournalEntry.Mood, note: String, on date: Date = .now, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = entries.firstIndex(where: { $0.day == day }) {
            entries[index].mood = mood
            entries[index].note = trimmed
        } else {
            entries.append(HealthJournalEntry(day: day, mood: mood, note: trimmed))
            entries.sort { $0.day > $1.day }
        }
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
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
