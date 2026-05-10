import UIKit
import XCTest
@testable import Peptide

final class AvatarPresetTests: XCTestCase {

    func test_allPresets_haveUniqueIDs() {
        let ids = AvatarPreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Preset IDs must be unique to keep the picker stable")
    }

    func test_allPresets_useValidSFSymbols() {
        for preset in AvatarPreset.all {
            XCTAssertNotNil(
                UIImage(systemName: preset.symbol),
                "Preset \(preset.id) references missing SF Symbol \(preset.symbol)"
            )
        }
    }

    func test_renderJPEGData_producesNonEmptyJPEG() {
        guard let preset = AvatarPreset.all.first else {
            XCTFail("AvatarPreset.all should never be empty")
            return
        }
        let data = preset.renderJPEGData(side: 256)
        XCTAssertNotNil(data)
        // JPEG starts with 0xFFD8 magic bytes — sanity check that we wrote a
        // real JPEG, not just any non-nil Data.
        let first = data?.first ?? 0
        let second = data?.dropFirst().first ?? 0
        XCTAssertEqual(first, 0xFF)
        XCTAssertEqual(second, 0xD8)
    }

    func test_renderJPEGData_producesSquareImage() {
        guard let preset = AvatarPreset.all.first,
              let data = preset.renderJPEGData(side: 200),
              let image = UIImage(data: data)
        else {
            XCTFail("Preset must render to a decodable square image")
            return
        }
        XCTAssertEqual(image.size.width, image.size.height, accuracy: 1)
    }

    func test_renderJPEGData_atLargerSide_producesLargerOutput() {
        let preset = AvatarPreset.all[0]
        guard let small = preset.renderJPEGData(side: 128),
              let large = preset.renderJPEGData(side: 1024) else {
            XCTFail("Both sizes should encode")
            return
        }
        XCTAssertLessThan(small.count, large.count)
    }
}
