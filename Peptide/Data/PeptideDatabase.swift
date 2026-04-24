import Foundation

enum PeptideDatabase {

    /// Cached peptide list, loaded once on first access.
    static var shared: [Peptide] { loaded.peptides }

    /// Educational/safety disclaimer surfaced in onboarding, About, and on
    /// each peptide detail screen. Source: `peptides.json`.
    static var disclaimer: String { loaded.disclaimer }

    private static let loaded: (peptides: [Peptide], disclaimer: String) = load()

    private static let fallbackDisclaimer = """
    This information is for educational purposes only. It does not constitute \
    medical advice. Many peptides referenced are research chemicals not approved \
    for human use. Always consult a qualified healthcare provider before \
    starting, changing, or stopping any protocol.
    """

    // MARK: - Decoding DTOs

    private struct Payload: Decodable {
        let version: Int
        let generatedAt: String
        let count: Int
        let disclaimer: String
        let peptides: [PeptideDTO]

        enum CodingKeys: String, CodingKey {
            case version, count, disclaimer, peptides
            case generatedAt = "generated_at"
        }
    }

    private struct PeptideDTO: Decodable {
        let id: Int
        let name: String
        let abbreviation: String
        let category: String
        let description: String
        let benefits: [String]
        let dosageRange: String
        let frequency: String
        let halfLife: String
        let adminRoute: String
        let mechanism: String
        let contraindications: [String]
        let sideEffects: [String]
        let commonStacks: [String]
        let regulatoryStatus: String
        let imageSystemName: String
        let researchLinks: [ResearchLinkDTO]
        let molecular: MolecularDTO?
    }

    private struct ResearchLinkDTO: Decodable {
        let title: String
        let source: String
        let year: Int
        let pmid: String?
        let doi: String?
        let url: String?
    }

    private struct MolecularDTO: Decodable {
        let cid: Int?
        let molecularFormula: String?
        let molecularWeight: String?
        let smiles: String?
        let pubchemUrl: String?

        enum CodingKeys: String, CodingKey {
            case cid, smiles
            case molecularFormula = "molecular_formula"
            case molecularWeight = "molecular_weight"
            case pubchemUrl = "pubchem_url"
        }
    }

    // MARK: - Loading

    private static func load() -> (peptides: [Peptide], disclaimer: String) {
        guard let url = Bundle.main.url(forResource: "peptides", withExtension: "json") else {
            assertionFailure("peptides.json not found in bundle — using fallback mocks")
            return (MockPeptides.fallback, fallbackDisclaimer)
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return (payload.peptides.map(map), payload.disclaimer)
        } catch {
            assertionFailure("Failed to decode peptides.json: \(error)")
            return (MockPeptides.fallback, fallbackDisclaimer)
        }
    }

    // MARK: - Mapping

    private static func map(_ dto: PeptideDTO) -> Peptide {
        Peptide(
            id: stableUUID(from: dto.id),
            name: dto.name,
            abbreviation: dto.abbreviation,
            category: mapCategory(dto.category),
            description: dto.description,
            benefits: dto.benefits,
            dosageRange: dto.dosageRange,
            frequency: dto.frequency,
            halfLife: dto.halfLife,
            adminRoute: dto.adminRoute,
            researchLinks: dto.researchLinks.map { link in
                ResearchLink(
                    title: link.title,
                    source: link.source,
                    year: link.year,
                    pmid: link.pmid ?? "",
                    doi: link.doi ?? "",
                    url: link.url ?? ""
                )
            },
            imageSystemName: dto.imageSystemName,
            mechanism: dto.mechanism,
            contraindications: dto.contraindications,
            sideEffects: dto.sideEffects,
            commonStacks: dto.commonStacks,
            regulatoryStatus: dto.regulatoryStatus,
            molecular: dto.molecular.map { mol in
                MolecularData(
                    cid: mol.cid,
                    formula: mol.molecularFormula ?? "",
                    weight: mol.molecularWeight ?? "",
                    smiles: mol.smiles ?? "",
                    pubchemURL: mol.pubchemUrl ?? ""
                )
            }
        )
    }

    /// Deterministic UUID from a peptide index, stable across launches.
    private static func stableUUID(from id: Int) -> UUID {
        let hex = String(format: "50455054-4944-4500-%04X-0000%08X", (id >> 32) & 0xFFFF, id & 0xFFFFFFFF)
        return UUID(uuidString: hex) ?? UUID()
    }

    private static func mapCategory(_ raw: String) -> PeptideCategory {
        guard let category = PeptideCategory(rawValue: raw) else {
            assertionFailure("Unknown peptide category: \(raw)")
            return .recovery
        }
        return category
    }
}
