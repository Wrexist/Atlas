import Foundation

/// Exhaustive catalog manifest, generated and checked by exercise-art-catalog.py.
/// Pending art deliberately resolves to the exercise's muscle map. No aliases.
enum ExerciseVisualAssets {
    struct Record: Codable, Sendable {
        let id: String
        let status: String
        let asset: String?
    }

    static let records: [Record] = {
        guard let url = Bundle.main.url(forResource: "exercise-visuals", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return decoded
    }()

    private static let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func poster(for exerciseID: String) -> String? {
        guard let record = byID[exerciseID], record.status == "illustrated" else { return nil }
        return record.asset
    }
}
