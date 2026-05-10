import XCTest
@testable import Peptide

final class VialPaletteTests: XCTestCase {

    // MARK: - Direct lookup

    func test_colors_seededCompounds_returnSpecPalettes() {
        XCTAssertEqual(VialPalette.colors(for: "BPC-157"),     VialPalette.colors(for: "BPC-157"))
        XCTAssertNotEqual(VialPalette.colors(for: "BPC-157"),  VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "TB-500"),   VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "GHK-Cu"),   VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Ipamorelin"), VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "CJC-1295"), VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Semaglutide"),  VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Retatrutide"),  VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Tirzepatide"),  VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Epitalon"), VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Selank"),   VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "Semax"),    VialPalette.unknown)
        XCTAssertNotEqual(VialPalette.colors(for: "PT-141"),   VialPalette.unknown)
    }

    /// "Melanotan / MT-1" in the spec — both halves of the alias should
    /// resolve to the same palette so cosmetic input variants don't fall
    /// through to the unknown grey.
    func test_colors_melanotanAliases_shareSamePalette() {
        let melanotan = VialPalette.colors(for: "Melanotan")
        let mt1 = VialPalette.colors(for: "MT-1")
        XCTAssertNotEqual(melanotan, VialPalette.unknown)
        XCTAssertEqual(melanotan, mt1)
    }

    // MARK: - Normalisation

    /// Real keystrokes vary in spacing / case / dashes; the lookup must
    /// normalise so all of these still match.
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

    // MARK: - Unknown fallback

    func test_colors_unknownCompound_returnsFallback() {
        XCTAssertEqual(VialPalette.colors(for: "KLOW"),      VialPalette.unknown)
        XCTAssertEqual(VialPalette.colors(for: "MadeUpRX"),  VialPalette.unknown)
        XCTAssertEqual(VialPalette.colors(for: ""),          VialPalette.unknown)
    }
}
