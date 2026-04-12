import Foundation

enum PeptideDatabase {

    /// Cached peptide list, loaded once on first access.
    static let shared: [Peptide] = load()

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

    private static func load() -> [Peptide] {
        guard let url = Bundle.main.url(forResource: "peptides", withExtension: "json") else {
            assertionFailure("peptides.json not found in bundle — using fallback mocks")
            return MockPeptides.fallback
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.peptides.map(map)
        } catch {
            assertionFailure("Failed to decode peptides.json: \(error)")
            return MockPeptides.fallback
        }
    }

    // MARK: - Mapping

    private static func map(_ dto: PeptideDTO) -> Peptide {
        Peptide(
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

    private static func mapCategory(_ raw: String) -> PeptideCategory {
        switch raw {
        case "growth": .growth
        case "recovery": .recovery
        case "cognitive": .cognitive
        case "antiAging": .antiAging
        case "immune": .immune
        case "metabolic": .metabolic
        default: .recovery
        }
    }
}
