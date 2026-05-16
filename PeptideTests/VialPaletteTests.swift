import XCTest
@testable import Peptide

final class VialPaletteTests: XCTestCase {

    // MARK: - Determinism

    /// Same input must always return the same palette across calls.
    /// The generated fallback uses a hash of the normalised name, so
    /// "Cerebrolysin" today and "Cerebrolysin" tomorrow must paint
    /// the same vial — otherwise the inventory shelf would shuffle
    /// colours between launches.
    func test_colors_sameInput_isDeterministic() {
        XCTAssertEqual(VialPalette.colors(for: "BPC-157"),       VialPalette.colors(for: "BPC-157"))
        XCTAssertEqual(VialPalette.colors(for: "Cerebrolysin"),  VialPalette.colors(for: "Cerebrolysin"))
        XCTAssertEqual(VialPalette.colors(for: "MadeUpRX"),      VialPalette.colors(for: "MadeUpRX"))
    }

    // MARK: - Curated compounds keep their hand-tuned colours

    /// Curated compounds must resolve to their hand-tuned palette
    /// even after the generator was added — the override path wins
    /// over the deterministic fallback.
    func test_colors_curatedCompounds_haveDistinctPalettes() {
        // Curated entries each have their own hand-tuned palette — no
        // two of the marquee compounds are allowed to alias to each
        // other.
        let curated = [
            "BPC-157", "TB-500", "GHK-Cu", "Ipamorelin", "CJC-1295",
            "Semaglutide", "Retatrutide", "Tirzepatide", "Epitalon",
            "Selank", "Semax", "PT-141",
        ].map { VialPalette.colors(for: $0) }

        for i in 0..<curated.count {
            for j in (i + 1)..<curated.count {
                XCTAssertNotEqual(curated[i], curated[j],
                                  "Curated palettes must not collide (\(i) vs \(j))")
            }
        }
    }

    /// "Melanotan / MT-1" — both halves of the alias resolve to the
    /// same palette so cosmetic input variants stay in lockstep.
    func test_colors_melanotanAliases_shareSamePalette() {
        let melanotan = VialPalette.colors(for: "Melanotan")
        let mt1 = VialPalette.colors(for: "MT-1")
        XCTAssertEqual(melanotan, mt1)
    }

    // MARK: - Normalisation

    /// Real keystrokes vary in spacing / case / dashes; the lookup
    /// normalises so all of these still match the same palette.
    func test_colors_caseAndPunctuationVariants_collapseToSamePalette() {
        let canonical = VialPalette.colors(for: "BPC-157")
        XCTAssertEqual(VialPalette.colors(for: "bpc-157"),  canonical)
        XCTAssertEqual(VialPalette.colors(for: "BPC 157"),  canonical)
        XCTAssertEqual(VialPalette.colors(for: "bpc157"),   canonical)
        XCTAssertEqual(VialPalette.colors(for: "BPC.157"),  canonical)
    }

    func test_normalize_stripsAllNonAlphanumerics() {
        XCTAssertEqual(VialPalette.normalize("BPC-157"),       "bpc157")
        XCTAssertEqual(VialPalette.normalize("Melanotan / MT-1"), "melanotanmt1")
        XCTAssertEqual(VialPalette.normalize("  CJC-1295 "),   "cjc1295")
        XCTAssertEqual(VialPalette.normalize("GHK-Cu"),        "ghkcu")
    }

    // MARK: - No more "everything-is-gray" fallback

    /// The whole point of the redesign: a compound the user adds
    /// (Cerebrolysin, DSIP, Sermorelin) should NOT all collapse to
    /// the same gray palette anymore. They each get a distinct
    /// generated palette tied to their inferred category.
    func test_colors_unknownCompounds_getDistinctPalettes() {
        let cereb = VialPalette.colors(for: "Cerebrolysin")
        let dsip  = VialPalette.colors(for: "DSIP")
        let serm  = VialPalette.colors(for: "Sermorelin")
        XCTAssertNotEqual(cereb, dsip,
                          "Cerebrolysin and DSIP must not paint identically")
        XCTAssertNotEqual(cereb, serm)
        XCTAssertNotEqual(dsip,  serm)
    }

    // MARK: - Category steers the cap tint

    /// Same-category compounds share a cap tint (the "family at a
    /// glance" promise from the redesign brief). Cognitive peptides
    /// all wear the dark-indigo cap; growth peptides all wear brass.
    func test_colors_sameCategoryCompounds_shareCapTint() {
        let cognitive = VialPalette.colors(for: "Cerebrolysin", category: .cognitive)
        let cognitive2 = VialPalette.colors(for: "DSIP",        category: .cognitive)
        XCTAssertEqual(cognitive.capTint, cognitive2.capTint)
        XCTAssertEqual(cognitive.capTint, .darkIndigo)

        let growth1 = VialPalette.colors(for: "Sermorelin", category: .growth)
        let growth2 = VialPalette.colors(for: "GHRP-6",     category: .growth)
        XCTAssertEqual(growth1.capTint, growth2.capTint)
        XCTAssertEqual(growth1.capTint, .brass)
    }

    /// Inference path: when no category is passed, the palette should
    /// still resolve to the right family based on the name.
    func test_colors_inferredCategory_picksRightCapTint() {
        XCTAssertEqual(VialPalette.colors(for: "Cerebrolysin").capTint, .darkIndigo)
        XCTAssertEqual(VialPalette.colors(for: "Sermorelin").capTint,   .brass)
        XCTAssertEqual(VialPalette.colors(for: "Semaglutide").capTint,  .copper)
    }
}
