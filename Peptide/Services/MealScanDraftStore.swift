import Foundation
import CryptoKit

struct MealScanDraft: Codable, Equatable {
    var version = 1
    var items: [EditableFoodItem]
    var photo: Data?
    var date: Date
    var category: MealCategory
    var suggestedName: String?
    var name: String
    var combine: Bool
    var pendingEntries: [MealEntry] = []
    var undoRequested = false
    var accountIdentity: Data?
}

#if DEBUG
extension MealScanDraft {
    /// Only used by an explicit screenshot-mode launch; never sends a photo.
    static func reviewFixture() -> Self {
        let item = EditableFoodItem(from: .init(name: "Oats with berries", quantityLabel: "1 bowl",
            grams: 200, calories: 280, proteinG: 12, carbsG: 42, fatG: 7, confidence: 0.8))
        return Self(items: [item], photo: nil, date: Date(), category: .breakfast,
                    suggestedName: "Breakfast bowl", name: "Breakfast bowl", combine: true)
    }
}
#endif

@MainActor
final class MealScanDraftStore {
    static let shared = MealScanDraftStore(url: URL.applicationSupportDirectory
        .appending(path: "MealScanDraft", directoryHint: .isDirectory).appending(path: "review.json"))
    let url: URL
    private(set) var generation = UUID()
    private var lastSaved: MealScanDraft?
    init(url: URL) { self.url = url }
    func load() throws -> MealScanDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try JSONDecoder().decode(MealScanDraft.self, from: Data(contentsOf: url))
        guard draft.version == 1, draft.accountIdentity == (try identity()) else { throw CocoaError(.coderReadCorrupt) }
        lastSaved = draft
        return draft
    }
    func save(_ draft: MealScanDraft) throws {
        var owned = draft
        owned.accountIdentity = try identity()
        guard owned != lastSaved else { return }
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(owned).write(to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastSaved = owned
    }
    private func identity() throws -> Data? {
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
        return Data(SHA256.hash(data: data))
    }
    func discard() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        lastSaved = nil
    }
    func resetForAccountChange() {
        generation = UUID()
        do { try discard() } catch { AppLog.persistence.error("Could not remove meal scan draft") }
    }
}
