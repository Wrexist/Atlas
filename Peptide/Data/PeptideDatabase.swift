import Foundation

enum PeptideDatabase {

    /// Cached peptide list, loaded once on first access.
    static var shared: [Peptide] { loaded.peptides }

    /// Educational/safety disclaimer surfaced in onboarding, About, and on
    /// each peptide detail screen. Source: `peptides.json`.
    static var disclaimer: String { loaded.disclaimer }

    private static let loaded: (peptides: [Peptide], disclaimer: String) = load()

    /// Resolves a free-form `commonStacks` entry (e.g. "BPC-157",
    /// "TB-500 (Thymosin Beta-4)", "Growth Hormone (HGH)") to a known peptide.
    /// Returns nil for non-peptide stack entries like "Alpha-GPC".
    static func peptide(matching stackEntry: String) -> Peptide? {
        let trimmed = stackEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidates: [String] = [trimmed]
        if let parenStart = trimmed.firstIndex(of: "(") {
            let prefix = trimmed[..<parenStart].trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { candidates.append(prefix) }

            let afterOpen = trimmed.index(after: parenStart)
            if let parenEnd = trimmed[afterOpen...].firstIndex(of: ")") {
                let inner = trimmed[afterOpen..<parenEnd].trimmingCharacters(in: .whitespacesAndNewlines)
                if !inner.isEmpty { candidates.append(inner) }
            }
        }

        for candidate in candidates {
            let key = candidate.lowercased()
            if let match = lookupIndex.byAbbreviation[key] { return match }
            if let match = lookupIndex.byName[key] { return match }
        }
        return nil
    }

    private static let lookupIndex: (byAbbreviation: [String: Peptide], byName: [String: Peptide]) = {
        var byAbbreviation: [String: Peptide] = [:]
        var byName: [String: Peptide] = [:]
        for peptide in shared {
            byAbbreviation[peptide.abbreviation.lowercased()] = peptide
            byName[peptide.name.lowercased()] = peptide
        }
        return (byAbbreviation, byName)
    }()

    private static let fallbackDisclaimer = """
    This information is for educational purposes only. Atlas does not \
    provide medical advice, recommend doses, prescribe, or calculate dosages. \
    The values shown are summaries of figures reported in the published \
    research literature, with citations on every peptide page. Many peptides \
    referenced are research chemicals not approved for human use in many \
    jurisdictions. Always consult a qualified, licensed healthcare provider \
    before starting, changing, or stopping any protocol.
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
            AppLog.database.error("peptides.json not found in bundle — using fallback mocks")
            assertionFailure("peptides.json not found in bundle — using fallback mocks")
            return (MockPeptides.fallback, fallbackDisclaimer)
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return (payload.peptides.map(map), payload.disclaimer)
        } catch {
            AppLog.database.error("Failed to decode peptides.json: \(error.localizedDescription, privacy: .public)")
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
            AppLog.database.warning("Unknown peptide category \"\(raw, privacy: .public)\" — bucketing as .other")
            return .other
        }
        return category
    }
}
