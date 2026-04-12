import Foundation

/// Replaces MockPeptides.all at runtime by loading peptides.json from the app bundle.
/// Drop peptides.json into Peptide/Resources/ and add to the Peptide target in project.yml.
///
/// Usage in DataStore.swift:
///     let allPeptides = PeptideDatabase.load()
///
enum PeptideDatabase {

    // MARK: - Decoding DTOs (match build_dataset.py output schema)

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

    /// Load peptides.json from the app bundle. Falls back to MockPeptides.all on failure.
    static func load() -> [Peptide] {
        guard let url = Bundle.main.url(forResource: "peptides", withExtension: "json") else {
            assertionFailure("peptides.json not found in bundle — falling back to mocks")
            return MockPeptides.all
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.peptides.map(map)
        } catch {
            assertionFailure("Failed to decode peptides.json: \(error)")
            return MockPeptides.all
        }
    }

    // MARK: - Mapping

    private static func map(_ dto: PeptideDTO) -> Peptide {
        Peptide(
            id: UUID(),
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
                    year: link.year
                )
            },
            imageSystemName: dto.imageSystemName
        )
    }

    private static func mapCategory(_ raw: String) -> PeptideCategory {
        switch raw {
        case "growth": return .growth
        case "recovery": return .recovery
        case "cognitive": return .cognitive
        case "antiAging": return .antiAging
        case "immune": return .immune
        case "metabolic": return .metabolic
        default: return .recovery
        }
    }
}
