import Foundation

/// Pure-function vial-fill math, extracted from `DataStore` so the
/// modulo / refill semantics are unit-testable in isolation.
///
/// The Home shelf renders a vial illustration per stacked peptide; the
/// liquid level falls as the user logs doses, then visually "refills"
/// every `dosesPerVial`-th completion. Empty shelves (zero logged
/// doses) render full so a brand-new install doesn't look broken.
enum VialInventoryLogic {

    /// Liquid-fill fraction for a compound's vial, derived from how many
    /// completed entries exist for that peptide. Wraps via modulo so the
    /// shelf visually "refills" each time the user crosses a vial
    /// boundary — reads as a believable vial swap on continuously-used
    /// compounds. A peptide with zero logged doses returns 1.0 so a
    /// brand-new shelf shows full vials, not empty ones.
    ///
    /// `dosesPerVial` is parameterized rather than hardcoded so DataStore
    /// can supply its `defaultDosesPerVial` constant (kept as a public
    /// surface for tests + future per-peptide overrides) without this
    /// file taking a dependency on DataStore.
    static func liquidLevel(
        for peptide: Peptide,
        in entries: [ProtocolEntry],
        dosesPerVial: Int
    ) -> Double {
        let doseCount = entries.filter { $0.peptide.id == peptide.id && $0.completed }.count
        guard doseCount != 0 else { return 1.0 }
        let consumed = doseCount % dosesPerVial
        // When the modulo lands exactly on the vial boundary the user
        // just finished a vial — show a fresh full one rather than an
        // empty one so the next dose drains from full again.
        if consumed == 0 { return 1.0 }
        return max(0.05, 1.0 - Double(consumed) / Double(dosesPerVial))
    }
}
