import Foundation
import OSLog

private let log = Logger(subsystem: "com.peptidesai.app", category: "PersistenceService")

final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory unavailable")
        }
        return url
    }

    private var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    private var protocolsURL: URL { documentsDirectory.appendingPathComponent("protocols.json") }
    private var entriesURL: URL { documentsDirectory.appendingPathComponent("entries.json") }
    private var profileURL: URL { documentsDirectory.appendingPathComponent("profile.json") }
    private var customPeptidesURL: URL { documentsDirectory.appendingPathComponent("custom-peptides.json") }
    private var widgetDataURL: URL? { sharedContainerURL?.appendingPathComponent("widget-data.json") }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    // MARK: - Save

    func saveProtocols(_ protocols: [PeptideProtocol]) {
        save(protocols, to: protocolsURL)
    }

    func saveEntries(_ entries: [ProtocolEntry]) {
        save(entries, to: entriesURL)
    }

    func saveProfile(_ profile: UserProfile) {
        save(profile, to: profileURL)
    }

    func saveCustomPeptides(_ peptides: [Peptide]) {
        save(peptides, to: customPeptidesURL)
    }

    // MARK: - Load

    func loadProtocols() -> [PeptideProtocol]? {
        load([PeptideProtocol].self, from: protocolsURL)
    }

    func loadEntries() -> [ProtocolEntry]? {
        load([ProtocolEntry].self, from: entriesURL)
    }

    func loadProfile() -> UserProfile? {
        load(UserProfile.self, from: profileURL)
    }

    func loadCustomPeptides() -> [Peptide]? {
        load([Peptide].self, from: customPeptidesURL)
    }

    // MARK: - Widget Data (Shared Container)

    func updateWidgetData(_ data: WidgetData) {
        guard let url = widgetDataURL else { return }
        save(data, to: url)
    }

    // MARK: - State

    var hasPersistedData: Bool {
        fileManager.fileExists(atPath: protocolsURL.path) ||
        fileManager.fileExists(atPath: entriesURL.path) ||
        fileManager.fileExists(atPath: profileURL.path)
    }

    func clearAll() {
        try? fileManager.removeItem(at: protocolsURL)
        try? fileManager.removeItem(at: entriesURL)
        try? fileManager.removeItem(at: profileURL)
        try? fileManager.removeItem(at: customPeptidesURL)
        if let url = widgetDataURL {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Renames legacy JSON files to `.migrated` so MigrationService knows not to re-run.
    /// Silently ignores files that don't exist.
    func archiveLegacyFiles() {
        for url in [protocolsURL, entriesURL, profileURL] {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let archived = url.deletingPathExtension().appendingPathExtension("migrated")
            try? fileManager.moveItem(at: url, to: archived)
        }
    }

    // MARK: - Private

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Failed to save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
