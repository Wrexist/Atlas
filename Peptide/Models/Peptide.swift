import Foundation

struct ResearchLink: Identifiable, Hashable, Codable {
    var id: UUID
    let title: String
    let source: String
    let year: Int

    enum CodingKeys: String, CodingKey {
        case id, title, source, year
    }

    init(id: UUID = UUID(), title: String, source: String, year: Int) {
        self.id = id
        self.title = title
        self.source = source
        self.year = year
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.source = try container.decode(String.self, forKey: .source)
        self.year = try container.decode(Int.self, forKey: .year)
    }
}

struct Peptide: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let abbreviation: String
    let category: PeptideCategory
    let description: String
    let benefits: [String]
    let dosageRange: String
    let frequency: String
    let halfLife: String
    let adminRoute: String
    let researchLinks: [ResearchLink]
    let imageSystemName: String

    static func == (lhs: Peptide, rhs: Peptide) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
