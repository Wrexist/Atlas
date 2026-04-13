import Foundation

final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    private var protocolsURL: URL { documentsDirectory.appendingPathComponent("protocols.json") }
    private var entriesURL: URL { documentsDirectory.appendingPathComponent("entries.json") }
    private var profileURL: URL { documentsDirectory.appendingPathComponent("profile.json") }
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

    // MARK: - Widget Data (Shared Container)

    func updateWidgetData(_ data: WidgetData) {
        guard let url = widgetDataURL else { return }
        save(data, to: url)
    }

    // MARK: - State

    var hasPersistedData: Bool {
        fileManager.fileExists(atPath: protocolsURL.path)
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
