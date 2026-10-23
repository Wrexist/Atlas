import Foundation

/// The peptide a dose row persists (audit A379). `StoredEntry` used to
/// carry the full catalog record — description, benefits, research
/// links, mechanism — on every dose, several KB per row synced through
/// CloudKit. New writes keep only the identity and the short fields
/// dose surfaces read; the full record is resolved by id at load.
///
/// The snapshot is still a `Peptide` encoded under the same keys, so
/// builds that predate it decode it without change, and rows written
/// before it (full records) decode through the same path.
enum EntryPeptideSnapshot {

    static func snapshot(of peptide: Peptide) -> Peptide {
        Peptide(
            id: peptide.id,
            name: peptide.name,
            abbreviation: peptide.abbreviation,
            category: peptide.category,
            description: "",
            benefits: [],
            dosageRange: peptide.dosageRange,
            frequency: peptide.frequency,
            halfLife: peptide.halfLife,
            adminRoute: peptide.adminRoute,
            researchLinks: [],
            imageSystemName: peptide.imageSystemName,
            regulatoryStatus: peptide.regulatoryStatus
        )
    }

    /// The full record for a decoded row: the known peptide with the
    /// same id, or the row's own copy (snapshot or legacy full record)
    /// when the id is no longer known — a deleted custom peptide, or one
    /// created on another device.
    static func resolve(_ stored: Peptide, in known: [UUID: Peptide]) -> Peptide {
        known[stored.id] ?? stored
    }

    /// First occurrence wins, so a caller lists its preferred source
    /// first; duplicate ids never trap.
    static func index(_ peptides: [Peptide]) -> [UUID: Peptide] {
        Dictionary(peptides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
