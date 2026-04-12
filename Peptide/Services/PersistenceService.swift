import Foundation

@MainActor
final class PersistenceService {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var protocolsURL: URL { documentsDirectory.appendingPathComponent("protocols.json") }
    private var entriesURL: URL { documentsDirectory.appendingPathComponent("entries.json") }
    private var profileURL: URL { documentsDirectory.appendingPathComponent("profile.json") }

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

    // MARK: - Load (nonisolated for widget/intent access)

    nonisolated func loadProtocols() -> [PeptideProtocol]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("protocols.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([PeptideProtocol].self, from: data)
    }

    nonisolated func loadEntries() -> [ProtocolEntry]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("entries.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([ProtocolEntry].self, from: data)
    }

    nonisolated func loadProfile() -> UserProfile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(UserProfile.self, from: data)
    }

    // MARK: - Peptide Database

    nonisolated func loadPeptideDatabase() -> [Peptide] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let url = Bundle.main.url(forResource: "peptides", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let peptides = try? decoder.decode([Peptide].self, from: data) else {
            return []
        }
        return peptides
    }

    // MARK: - State

    nonisolated var hasPersistedData: Bool {
        FileManager.default.fileExists(
            atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("protocols.json").path
        )
    }

    func clearAll() {
        try? fileManager.removeItem(at: protocolsURL)
        try? fileManager.removeItem(at: entriesURL)
        try? fileManager.removeItem(at: profileURL)
    }

    // MARK: - Private

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("PersistenceService: Failed to save to \(url.lastPathComponent): \(error)")
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
