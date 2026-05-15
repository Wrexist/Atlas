import Foundation

struct ResearchLink: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    let title: String
    let source: String
    let year: Int
    let pmid: String
    let doi: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case id, title, source, year, pmid, doi, url
    }

    init(id: UUID = UUID(), title: String, source: String, year: Int,
         pmid: String = "", doi: String = "", url: String = "") {
        self.id = id
        self.title = title
        self.source = source
        self.year = year
        self.pmid = pmid
        self.doi = doi
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.source = try container.decode(String.self, forKey: .source)
        self.year = try container.decode(Int.self, forKey: .year)
        self.pmid = try container.decodeIfPresent(String.self, forKey: .pmid) ?? ""
        self.doi = try container.decodeIfPresent(String.self, forKey: .doi) ?? ""
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

struct MolecularData: Hashable, Codable, Sendable {
    let cid: Int?
    let formula: String
    let weight: String
    let smiles: String
    let pubchemURL: String
}

struct Peptide: Identifiable, Hashable, Codable, Sendable {
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
    let mechanism: String
    let contraindications: [String]
    let sideEffects: [String]
    let commonStacks: [String]
    let regulatoryStatus: String
    let molecular: MolecularData?

    init(id: UUID = UUID(), name: String, abbreviation: String,
         category: PeptideCategory, description: String, benefits: [String],
         dosageRange: String, frequency: String, halfLife: String,
         adminRoute: String, researchLinks: [ResearchLink],
         imageSystemName: String, mechanism: String = "",
         contraindications: [String] = [], sideEffects: [String] = [],
         commonStacks: [String] = [], regulatoryStatus: String = "",
         molecular: MolecularData? = nil) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.category = category
        self.description = description
        self.benefits = benefits
        self.dosageRange = dosageRange
        self.frequency = frequency
        self.halfLife = halfLife
        self.adminRoute = adminRoute
        self.researchLinks = researchLinks
        self.imageSystemName = imageSystemName
        self.mechanism = mechanism
        self.contraindications = contraindications
        self.sideEffects = sideEffects
        self.commonStacks = commonStacks
        self.regulatoryStatus = regulatoryStatus
        self.molecular = molecular
    }

    static func == (lhs: Peptide, rhs: Peptide) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
