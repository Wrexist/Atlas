import UIKit

/// Notes the owner jots while using a TestFlight build: what felt off,
/// what's missing. Each note keeps the screen it was written on and a
/// screenshot, so it still makes sense days later. Kept on this device
/// only, and shared by hand as a Markdown file plus the screenshots.
struct FieldNote: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let screen: String
    let text: String
    let screenshotFilename: String?
}

@MainActor
final class FieldNoteStore {
    static let shared = FieldNoteStore()

    private(set) var notes: [FieldNote] = []

    private let directory: URL?
    private var notesURL: URL? { directory?.appendingPathComponent("notes.json") }

    init(directory: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("FieldNotes", isDirectory: true)) {
        self.directory = directory
        notes = load()
    }

    func add(text: String, screen: String, screenshot: UIImage?, now: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let directory else { return }
        createDirectoryIfNeeded()
        let id = UUID()
        var filename: String?
        if let jpeg = screenshot?.jpegData(compressionQuality: 0.7) {
            let name = "note-\(id.uuidString.prefix(8)).jpg"
            let options: Data.WritingOptions = [.atomic, .completeFileProtection]
            if (try? jpeg.write(to: directory.appendingPathComponent(name), options: options)) != nil {
                filename = name
            }
        }
        notes.append(FieldNote(id: id, createdAt: now, screen: screen, text: trimmed, screenshotFilename: filename))
        save()
    }

    /// The files to share: one Markdown list, newest first, plus every
    /// screenshot it names.
    func exportFiles() -> [URL] {
        guard let directory, !notes.isEmpty else { return [] }
        createDirectoryIfNeeded()
        let markdownURL = directory.appendingPathComponent("atlas-notes.md")
        guard (try? FieldNoteMarkdown.render(notes).write(to: markdownURL, atomically: true, encoding: .utf8)) != nil else {
            return []
        }
        let screenshots = notes.compactMap(\.screenshotFilename).map { directory.appendingPathComponent($0) }
        return [markdownURL] + screenshots
    }

    func deleteAll() {
        notes = []
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    private func load() -> [FieldNote] {
        guard let notesURL, let data = try? Data(contentsOf: notesURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FieldNote].self, from: data)) ?? []
    }

    private func save() {
        guard let notesURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(notes).write(to: notesURL, options: [.atomic, .completeFileProtection])
        } catch {
            AppLog.persistence.error("Field notes save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Screenshots can show health data, so the folder stays out of
    /// iCloud Backup like the other stores holding it.
    private func createDirectoryIfNeeded() {
        guard let directory, !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        PersistenceService.excludeFromBackup(directory)
    }
}

/// The shared Markdown: newest first, one heading per note with its
/// time and screen, then the text and the screenshot's file name.
enum FieldNoteMarkdown {
    static func render(_ notes: [FieldNote], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let blocks = notes.sorted { $0.createdAt > $1.createdAt }.map { note -> String in
            var block = "## \(formatter.string(from: note.createdAt)) · \(note.screen)\n\n\(note.text)\n"
            if let screenshot = note.screenshotFilename {
                block += "\nScreenshot: \(screenshot)\n"
            }
            return block
        }
        return "# Atlas notes (\(notes.count))\n\n" + blocks.joined(separator: "\n")
    }
}
