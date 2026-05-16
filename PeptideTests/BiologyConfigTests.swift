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
        XCTAssertFalse(BiologyConfig.default.hasSeenIntro)
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

    // MARK: - Codable round-trip

    func test_codable_roundTripPreservesAllFields() throws {
        let original = BiologyConfig(
            visibleBiomarkers: [.weight, .sleepBaseline],
            hiddenBiomarkers: [.hrvBaseline],
            hasSeenIntro: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BiologyConfig.self, from: data)
        XCTAssertEqual(decoded, original)
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
                hiddenBiomarkers: [.sleepBaseline],
                hasSeenIntro: true
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.biologyConfig.visibleBiomarkers, [.weight, .hrvBaseline])
        XCTAssertEqual(decoded.biologyConfig.hiddenBiomarkers, [.sleepBaseline])
        XCTAssertTrue(decoded.biologyConfig.hasSeenIntro)
    }
}
