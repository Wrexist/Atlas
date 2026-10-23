import XCTest
@testable import Peptide

final class ShareFormatTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ShareFormatTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_nothingRemembered_loadsDefault() {
        let format: ShareFormat = ShareFormatMemory.load(ShareFormatMemory.cycleCardKey, default: .story, from: defaults)
        XCTAssertEqual(format, .story)
    }

    func test_savedFormat_isLoadedBack() {
        for saved in ShareFormat.allCases {
            ShareFormatMemory.save(saved, ShareFormatMemory.cycleCardKey, to: defaults)
            let loaded: ShareFormat = ShareFormatMemory.load(ShareFormatMemory.cycleCardKey, default: .story, from: defaults)
            XCTAssertEqual(loaded, saved)
        }
    }

    func test_workoutFormat_isRememberedSeparatelyFromCycleCard() {
        ShareFormatMemory.save(ShareFormat.landscape, ShareFormatMemory.cycleCardKey, to: defaults)
        ShareFormatMemory.save(WorkoutShareFormat.reel, ShareFormatMemory.workoutKey, to: defaults)

        let cycle: ShareFormat = ShareFormatMemory.load(ShareFormatMemory.cycleCardKey, default: .story, from: defaults)
        let workout: WorkoutShareFormat = ShareFormatMemory.load(ShareFormatMemory.workoutKey, default: .story, from: defaults)
        XCTAssertEqual(cycle, .landscape)
        XCTAssertEqual(workout, .reel)
    }

    func test_unknownStoredFormat_fallsBackToDefault() {
        // A format a later release removed, or a hand-edited plist.
        defaults.set("panorama", forKey: ShareFormatMemory.workoutKey)
        let format: WorkoutShareFormat = ShareFormatMemory.load(ShareFormatMemory.workoutKey, default: .story, from: defaults)
        XCTAssertEqual(format, .story)
    }

    func test_pixelSizes_matchDestinationSpecs() {
        XCTAssertEqual(ShareFormat.story.pixelSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(ShareFormat.square.pixelSize, CGSize(width: 1080, height: 1080))
        XCTAssertEqual(ShareFormat.landscape.pixelSize, CGSize(width: 1200, height: 630))
    }

    func test_workoutFormats_logicalSizeTimesScale_isPixelSize() {
        // The workout canvases are laid out in points and rendered at
        // `renderScale`; a non-integral product would round the export.
        for format in WorkoutShareFormat.allCases {
            let logical = format.logicalSize
            XCTAssertEqual(logical.width * format.renderScale, format.pixelSize.width, accuracy: 0.001, "\(format)")
            XCTAssertEqual(logical.height * format.renderScale, format.pixelSize.height, accuracy: 0.001, "\(format)")
        }
    }

    func test_workoutSquareAndLandscape_shareTheCommonFormatSizes() {
        XCTAssertEqual(WorkoutShareFormat.square.pixelSize, ShareFormat.square.pixelSize)
        XCTAssertEqual(WorkoutShareFormat.landscape.pixelSize, ShareFormat.landscape.pixelSize)
        XCTAssertEqual(WorkoutShareFormat.landscape.layout, .wide)
        XCTAssertEqual(WorkoutShareFormat.square.layout, .compact)
    }
}
