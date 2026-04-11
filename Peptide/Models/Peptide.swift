import Foundation

struct ResearchLink: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let source: String
    let year: Int
}

struct Peptide: Identifiable, Hashable {
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
