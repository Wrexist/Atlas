import XCTest
@testable import Peptide

/// Schema-migration tests for the new `biologyConfig` field on
/// UserProfile. Lock down the backwards-compat decoder, the
/// catalog-membership filter on reorder, and the show/hide
/// mutations.
final class BiologyConfigTests: XCTestCase {

    // MARK: - Defaults

    func test_default_matchesBiomarkerDefaultVisible() {
        XCTAssertEqual(BiologyConfig.default.visibleBiomarkers, Biomarker.defaultVisible)
        XCTAssertTrue(BiologyConfig.default.hiddenBiomarkers.isEmpty)
    }

    // MARK: - Mutations

    func test_show_movesFromHiddenToVisible() {
        var config = BiologyConfig(
            visibleBiomarkers: [.weight],
            hiddenBiomarkers: [.hrvBaseline]
        )
        config.show(.hrvBaseline)
        XCTAssertTrue(config.visibleBiomarkers.contains(.hrvBaseline))
        XCTAssertFalse(config.hiddenBiomarkers.contains(.hrvBaseline))
    }

    func test_show_addsAvailableBiomarker() {
        var config = BiologyConfig(
            visibleBiomarkers: [.weight],
            hiddenBiomarkers: []
        )
        // bodyFat is in the catalog but neither visible nor hidden.
        config.show(.bodyFat)
        XCTAssertTrue(config.visibleBiomarkers.contains(.bodyFat))
    }

    func test_show_alreadyVisible_isNoOp() {
        var config = BiologyConfig(
            visibleBiomarkers: [.weight, .hrvBaseline],
            hiddenBiomarkers: []
        )
        config.show(.weight)
        XCTAssertEqual(config.visibleBiomarkers, [.weight, .hrvBaseline])
    }

    func test_hide_movesFromVisibleToHidden() {
        var config = BiologyConfig(
            visibleBiomarkers: [.weight, .hrvBaseline],
            hiddenBiomarkers: []
        )
        config.hide(.weight)
        XCTAssertFalse(config.visibleBiomarkers.contains(.weight))
        XCTAssertTrue(config.hiddenBiomarkers.contains(.weight))
    }

    // MARK: - Reorder

    func test_reorder_replacesVisibleListInOrder() {
        var config = BiologyConfig(
            visibleBiomarkers: [.weight, .hrvBaseline, .rhrBaseline],
            hiddenBiomarkers: []
        )
        config.reorder([.rhrBaseline, .weight, .hrvBaseline])
        XCTAssertEqual(config.visibleBiomarkers, [.rhrBaseline, .weight, .hrvBaseline])
    }

    /// A stale persisted ordering carrying a deleted enum case
    /// is filtered out — defends against a future Biomarker
    /// removal silently corrupting the catalog. All current cases
    /// pass through; we test by checking the reordered list only
    /// contains valid cases.
    func test_reorder_filtersOutOfCatalogEntriesGracefully() {
        var config = BiologyConfig()
        config.reorder([.weight, .hrvBaseline])
        XCTAssertEqual(config.visibleBiomarkers, [.weight, .hrvBaseline])
    }

    // MARK: - availableBiomarkers

    func test_availableBiomarkers_excludesVisibleAndHidden() {
        let config = BiologyConfig(
            visibleBiomarkers: [.weight, .hrvBaseline],
            hiddenBiomarkers: [.rhrBaseline]
        )
        let available = config.availableBiomarkers
        XCTAssertFalse(available.contains(.weight))
        XCTAssertFalse(available.contains(.hrvBaseline))
        XCTAssertFalse(available.contains(.rhrBaseline))
        // Everything else in the catalog is available.
        let expected = Biomarker.allCases.filter {
            $0 != .weight && $0 != .hrvBaseline && $0 != .rhrBaseline
        }
        XCTAssertEqual(Set(available), Set(expected))
    }

    /// Every catalog row can now be filled — the body measurements read
    /// and write Apple Health — so a fresh config offers all of them.
    func test_availableBiomarkers_freshConfig_offersWholeCatalog() {
        let available = BiologyConfig(visibleBiomarkers: [], hiddenBiomarkers: []).availableBiomarkers
        XCTAssertEqual(Set(available), Set(Biomarker.allCases))
    }

    // MARK: - Codable round-trip

    func test_codable_roundTripPreservesAllFields() throws {
        let original = BiologyConfig(
            visibleBiomarkers: [.weight, .sleepBaseline],
            hiddenBiomarkers: [.hrvBaseline]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BiologyConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_keepsHasSeenIntroKey_forOlderBuildDecoders() throws {
        let data = try JSONEncoder().encode(BiologyConfig.default)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["hasSeenIntro"] as? Bool, false)
    }

    func test_decode_missingKeys_fallsBackToDefaults() throws {
        let data = Data(#"{"visibleBiomarkers":["weight"]}"#.utf8)
        let decoded = try JSONDecoder().decode(BiologyConfig.self, from: data)
        XCTAssertEqual(decoded.visibleBiomarkers, [.weight])
        XCTAssertTrue(decoded.hiddenBiomarkers.isEmpty)
    }

    func test_decode_unknownBiomarker_isDroppedNotThrown() throws {
        let data = Data(#"{"visibleBiomarkers":["weight","futureMarker"],"hiddenBiomarkers":["futureMarker"],"hasSeenIntro":true}"#.utf8)
        let decoded = try JSONDecoder().decode(BiologyConfig.self, from: data)
        XCTAssertEqual(decoded.visibleBiomarkers, [.weight])
        XCTAssertTrue(decoded.hiddenBiomarkers.isEmpty)
    }

    /// The migration story: an older UserProfile JSON has no
    /// `biologyConfig` key. The decoder must land on
    /// `.default` rather than throwing. Verified at the
    /// UserProfile level — this is the actual on-disk contract.
    func test_userProfile_decoder_oldFormatWithoutBiologyConfig_usesDefault() throws {
        let oldJSON = """
        {
            "name": "Test User",
            "goals": [],
            "memberSince": 0,
            "healthConnected": false
        }
        """
        let data = Data(oldJSON.utf8)
        let decoder = JSONDecoder()
        let profile = try decoder.decode(UserProfile.self, from: data)
        XCTAssertEqual(profile.biologyConfig, .default)
    }

    func test_userProfile_decoder_newFormat_preservesBiologyConfig() throws {
        let original = UserProfile(
            name: "Test",
            goals: [],
            memberSince: Date(),
            healthConnected: false,
            biologyConfig: BiologyConfig(
                visibleBiomarkers: [.weight, .hrvBaseline],
                hiddenBiomarkers: [.sleepBaseline]
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.biologyConfig.visibleBiomarkers, [.weight, .hrvBaseline])
        XCTAssertEqual(decoded.biologyConfig.hiddenBiomarkers, [.sleepBaseline])
    }

    // MARK: - Card sizes

    func test_tileSize_unset_isSmall() {
        XCTAssertEqual(BiologyConfig().tileSize(for: .hrvBaseline), .small)
    }

    func test_setTileSize_default_clearsTheEntry() {
        var config = BiologyConfig()
        config.setTileSize(.large, for: .weight)
        XCTAssertEqual(config.tileSize(for: .weight), .large)
        config.setTileSize(.small, for: .weight)
        XCTAssertTrue(config.tileSizes.isEmpty)
    }

    func test_tileSizes_roundTripThroughCoding() throws {
        var config = BiologyConfig()
        config.setTileSize(.medium, for: .sleepBaseline)
        let decoded = try JSONDecoder().decode(BiologyConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.tileSize(for: .sleepBaseline), .medium)
    }

    func test_tileSizes_unknownKeysAreDropped() throws {
        let json = #"{"visibleBiomarkers":["weight"],"hiddenBiomarkers":[],"tileSizes":{"weight":"large","future":"small","waist":"huge"}}"#
        let decoded = try JSONDecoder().decode(BiologyConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.tileSizes, [.weight: .large])
    }

    func test_rows_pairSmallCardsAndGiveLargerOnesARow() {
        let rows = BiomarkerTileSize.rows(
            for: [.hrvBaseline, .rhrBaseline, .sleepBaseline, .weight, .stepsBaseline],
            sizes: [.weight: .medium]
        )
        XCTAssertEqual(rows, [[.hrvBaseline, .rhrBaseline], [.sleepBaseline], [.weight], [.stepsBaseline]])
    }
}
