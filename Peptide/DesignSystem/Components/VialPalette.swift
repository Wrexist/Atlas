import SwiftUI

/// Colour palette for a single vial. Picked by `colors(for:)` —
/// curated compound-name overrides win first, then category-based
/// defaults, then a deterministic hash fallback. The deterministic
/// fallback exists so every compound the user might add (Cerebrolysin,
/// DSIP, Sermorelin, …) lands on a stable, unique colour instead of
/// collapsing to a single gray "unknown" palette.
struct VialPalette: Equatable, Sendable {
    let fill: Color
    let highlight: Color
    let capTint: CapTint

    /// Cap-tint family. Tied to category so a glance across the shelf
    /// reads as "these are all cognitive peptides" — same metallic
    /// finish — without having to inspect labels. Within a family the
    /// individual hue of the liquid still distinguishes each compound.
    enum CapTint: Equatable, Sendable {
        case silver        // recovery / other
        case copper        // metabolic
        case roseGold      // antiAging
        case brass         // growth
        case gunmetal      // immune
        case darkIndigo    // cognitive
    }

    /// Resolves a palette for a compound. `category` is the preferred
    /// driver — same-category compounds share a cap family + a base
    /// hue, with a small per-compound offset so two cognitive peptides
    /// (e.g. Semax, Selank) read as siblings rather than identicals.
    /// When category is nil, we fall back to inferring from the
    /// compound name (`PeptideCategory.inferred(forName:)`) so legacy
    /// call sites that only have a name still get coherent styling.
    static func colors(
        for compoundName: String,
        category: PeptideCategory? = nil
    ) -> VialPalette {
        let key = normalize(compoundName)
        if let override = curated[key] { return override }
        let resolvedCategory = category ?? PeptideCategory.inferred(forName: compoundName)
        return generated(forKey: key, category: resolvedCategory)
    }

    /// Strips dashes / spaces / dots and lowercases so cosmetic
    /// variants of the same compound name don't fall through to the
    /// generated palette. Exposed for tests; not API surface.
    static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Curated compounds
    //
    // Hand-tuned palettes for the most common compounds — these win
    // over the category default so the marquee peptides have a
    // recognisable visual identity across screens.

    private static let curated: [String: VialPalette] = [
        "bpc157":      .init(fill: hex(0x4FB590), highlight: hex(0x9FE1CB), capTint: .silver),
        "tb500":       .init(fill: hex(0xE69020), highlight: hex(0xFAC775), capTint: .copper),
        "ghkcu":       .init(fill: hex(0x2C7BD0), highlight: hex(0x7FB5EA), capTint: .silver),
        "ipamorelin":  .init(fill: hex(0x6E66D2), highlight: hex(0xAFA9EC), capTint: .brass),
        "cjc1295":     .init(fill: hex(0x4A40B0), highlight: hex(0x7F77DD), capTint: .brass),
        "semaglutide": .init(fill: hex(0x568416), highlight: hex(0x97C459), capTint: .copper),
        "retatrutide": .init(fill: hex(0x2F5A0E), highlight: hex(0x639922), capTint: .copper),
        "tirzepatide": .init(fill: hex(0xC04A72), highlight: hex(0xED93B1), capTint: .copper),
        "melanotan":   .init(fill: hex(0xC8552C), highlight: hex(0xF0997B), capTint: .roseGold),
        "mt1":         .init(fill: hex(0xC8552C), highlight: hex(0xF0997B), capTint: .roseGold),
        "epitalon":    .init(fill: hex(0x0C5F4A), highlight: hex(0x1D9E75), capTint: .roseGold),
        "selank":      .init(fill: hex(0x1554A0), highlight: hex(0x378ADD), capTint: .darkIndigo),
        "semax":       .init(fill: hex(0x093A6F), highlight: hex(0x185FA5), capTint: .darkIndigo),
        "pt141":       .init(fill: hex(0x8A2D4B), highlight: hex(0xD4537E), capTint: .roseGold),
    ]

    // MARK: - Category bases
    //
    // Each category has a base hue + cap finish. Same-category
    // compounds get the cap finish; the liquid hue tilts ±10° from
    // the base so two siblings sit visibly close on a colour wheel
    // but don't look identical.

    private struct CategoryBase {
        let hue: Double            // 0…1
        let saturation: Double
        let brightness: Double
        let capTint: CapTint
    }

    private static func categoryBase(_ category: PeptideCategory) -> CategoryBase {
        switch category {
        case .cognitive:
            return .init(hue: 260.0 / 360, saturation: 0.50, brightness: 0.62, capTint: .darkIndigo)
        case .recovery:
            return .init(hue: 195.0 / 360, saturation: 0.55, brightness: 0.62, capTint: .silver)
        case .growth:
            return .init(hue: 130.0 / 360, saturation: 0.55, brightness: 0.58, capTint: .brass)
        case .metabolic:
            return .init(hue:  28.0 / 360, saturation: 0.75, brightness: 0.65, capTint: .copper)
        case .antiAging:
            return .init(hue:  44.0 / 360, saturation: 0.55, brightness: 0.68, capTint: .roseGold)
        case .immune:
            return .init(hue: 350.0 / 360, saturation: 0.55, brightness: 0.60, capTint: .gunmetal)
        case .other:
            return .init(hue: 210.0 / 360, saturation: 0.20, brightness: 0.58, capTint: .silver)
        }
    }

    /// Deterministic per-compound palette derived from a hash of the
    /// normalised name + the category base. Same compound always
    /// resolves to the same colour across launches.
    private static func generated(forKey key: String, category: PeptideCategory) -> VialPalette {
        let base = categoryBase(category)
        let offset = hueOffset(forKey: key)
        let liquidHue = wrap(base.hue + offset)
        let fill      = Color(hue: liquidHue, saturation: base.saturation,        brightness: base.brightness)
        let highlight = Color(hue: liquidHue, saturation: base.saturation * 0.75, brightness: min(1.0, base.brightness + 0.18))
        return VialPalette(fill: fill, highlight: highlight, capTint: base.capTint)
    }

    /// Maps a normalised compound key to a ±10° hue offset so two
    /// compounds in the same category land near each other on the
    /// wheel without colliding. djb2 is fast, stable across processes,
    /// and gives a uniform distribution for short strings.
    private static func hueOffset(forKey key: String) -> Double {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        // ±10° (= ±0.0278 of the 0…1 hue circle).
        let normalised = Double(hash % 1000) / 1000.0   // 0…1
        return (normalised - 0.5) * (20.0 / 360.0)
    }

    private static func wrap(_ hue: Double) -> Double {
        var h = hue
        while h < 0 { h += 1 }
        while h >= 1 { h -= 1 }
        return h
    }

    // Tiny hex helper local to this file. The app-wide `Color(hex:)`
    // exists but is in a different module of the design system and
    // pulling it in would bloat the import surface — three lines here
    // beats a cross-module dependency.
    private static func hex(_ value: UInt32) -> Color {
        Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

// MARK: - Cap rendering

extension VialPalette.CapTint {
    /// Gradient stops drawn into the cap rounded-rectangle. Picked to
    /// read as a metallic finish in dark UI — three stops, top-to-
    /// bottom, with a glint near the top edge.
    var gradient: LinearGradient {
        LinearGradient(
            colors: stops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var stops: [Color] {
        switch self {
        case .silver:
            return [Color(white: 0.95), Color(white: 0.78), Color(white: 0.62)]
        case .copper:
            return [Color(red: 0.92, green: 0.70, blue: 0.50),
                    Color(red: 0.78, green: 0.51, blue: 0.32),
                    Color(red: 0.55, green: 0.34, blue: 0.18)]
        case .roseGold:
            return [Color(red: 0.96, green: 0.80, blue: 0.74),
                    Color(red: 0.86, green: 0.62, blue: 0.55),
                    Color(red: 0.64, green: 0.42, blue: 0.38)]
        case .brass:
            return [Color(red: 0.92, green: 0.83, blue: 0.55),
                    Color(red: 0.76, green: 0.62, blue: 0.30),
                    Color(red: 0.52, green: 0.41, blue: 0.16)]
        case .gunmetal:
            return [Color(white: 0.55), Color(white: 0.36), Color(white: 0.22)]
        case .darkIndigo:
            return [Color(red: 0.55, green: 0.54, blue: 0.68),
                    Color(red: 0.35, green: 0.34, blue: 0.48),
                    Color(red: 0.20, green: 0.19, blue: 0.30)]
        }
    }
}

// MARK: - Category inference

extension PeptideCategory {
    /// Best-effort category lookup by compound name. Used when a call
    /// site has only the name (e.g. calendar marks that don't carry
    /// the full Peptide model). Mirrors the canonical mapping in
    /// MockPeptides.swift; expand here when new compounds ship.
    static func inferred(forName name: String) -> PeptideCategory {
        let key = VialPalette.normalize(name)
        return inferenceMap[key] ?? .other
    }

    private static let inferenceMap: [String: PeptideCategory] = [
        // Growth / GH secretagogues
        "bpc157":              .growth,
        "tb500":               .growth,
        "thymosinbeta4":       .growth,
        "thymosinbeta4fragment": .growth,
        "igf1":                .growth,
        "igf1lr3":             .growth,
        "cjc1295":             .growth,
        "cjc1295withdac":      .growth,
        "ipamorelin":          .growth,
        "sermorelin":          .growth,
        "ghrp2":               .growth,
        "ghrp6":               .growth,
        "hexarelin":           .growth,

        // Recovery / repair
        "ghkcu":               .recovery,
        "kpv":                 .recovery,

        // Cognitive
        "semax":               .cognitive,
        "selank":              .cognitive,
        "dihexa":              .cognitive,
        "cerebrolysin":        .cognitive,
        "dsip":                .cognitive,
        "noopept":             .cognitive,
        "p21":                 .cognitive,

        // Anti-aging
        "epitalon":            .antiAging,
        "ss31":                .antiAging,
        "humanin":              .antiAging,

        // Immune
        "thymosinalpha1":      .immune,
        "ll37":                .immune,

        // Metabolic
        "tesamorelin":         .metabolic,
        "aod9604":             .metabolic,
        "semaglutide":         .metabolic,
        "retatrutide":         .metabolic,
        "tirzepatide":         .metabolic,
        "mots-c":              .metabolic,
        "motsc":               .metabolic,

        // Other / specialty
        "melanotan":           .other,
        "mt1":                 .other,
        "pt141":                .other,
    ]
}
